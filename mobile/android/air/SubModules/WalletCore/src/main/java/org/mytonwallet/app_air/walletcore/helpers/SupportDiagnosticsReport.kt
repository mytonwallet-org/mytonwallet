package org.mytonwallet.app_air.walletcore.helpers

import android.app.ActivityManager
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.os.StatFs
import android.os.SystemClock
import android.view.Display
import androidx.core.content.pm.PackageInfoCompat
import androidx.webkit.WebViewCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.native_enclave.EnclaveManager
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.sdkStorage.WSdkInstallationStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.AccountStore

object SupportDiagnosticsReport {
    private const val SCHEMA_VERSION = 1

    fun collect(context: Context): JSONObject {
        val generatedAt = System.currentTimeMillis()
        val inspectionErrors = JSONObject()
        val currentAccountId = AccountStore.activeAccountId
        val orderedAccountIds = WGlobalStorage.getStoredOrderedAccountIds()
        val databaseAccounts = (
            WGlobalStorage.accountIds().toList() + WGlobalStorage.temporaryAddedAccountIds
            ).distinct().associateWith { WGlobalStorage.getAccount(it) }
        val secureInspection = inspectSecureAccounts()
        secureInspection.error?.let { inspectionErrors.put("secureStorageAccounts", it) }

        val enclave = EnclaveManager.sharedInstance
        val configuredAuthTypes = buildList {
            if (enclave?.isPasscodeAuthConfigured == true) add("passcode")
            if (enclave?.isBiometricAuthConfigured == true) add("biometric")
        }
        val storedEncryptedAccountIds = databaseAccounts
            .filterValues { it != null && isStoredEncrypted(it) }
            .keys
        val enclaveSecretAccountIds = if (configuredAuthTypes.isEmpty()) {
            null
        } else {
            try {
                requireNotNull(enclave) { "EnclaveManager is not initialized" }
                storedEncryptedAccountIds.filterTo(mutableSetOf()) { enclave.hasSecret(it) }
            } catch (e: Exception) {
                inspectionErrors.put("enclaveSecrets", e.javaClass.name)
                null
            }
        }
        val missingEnclaveSecretAccountIds =
            enclaveSecretAccountIds?.let { storedEncryptedAccountIds - it }
        val isLegacyMigrationPending = enclave != null && try {
            LegacyMigration.needsMigration()
        } catch (e: Exception) {
            inspectionErrors.put("legacyMigration", e.javaClass.name)
            true
        }

        val accountItems = makeAccountItems(
            databaseAccounts = databaseAccounts,
            currentAccountId = currentAccountId,
            orderedAccountIds = orderedAccountIds,
            secureInspection = secureInspection,
            hasConfiguredAuth = configuredAuthTypes.isNotEmpty(),
            enclaveSecretAccountIds = enclaveSecretAccountIds,
            isLegacyMigrationPending = isLegacyMigrationPending
        )
        val databaseAccountIds = databaseAccounts.keys
        val secureAccountIds = secureInspection.accountIds

        return JSONObject()
            .put("schemaVersion", SCHEMA_VERSION)
            .put("platform", "android")
            .put("generatedAt", formatDate(generatedAt))
            .put("app", makeAppInfo(context))
            .put("device", makeDeviceInfo(context))
            .put("installation", makeInstallationInfo())
            .put(
                "accounts",
                JSONObject()
                    .put("currentAccountId", currentAccountId.orNull())
                    .put("orderedAccountIds", JSONArray(orderedAccountIds))
                    .put("databaseAccountIds", databaseAccountIds.toSortedJson())
                    .put("secureStorageAccountIds", secureAccountIds?.toSortedJson().orNull())
                    .put(
                        "secureStorageOnlyAccountIds",
                        secureAccountIds?.let { it - databaseAccountIds }?.toSortedJson().orNull()
                    )
                    .put(
                        "databaseOnlyAccountIds",
                        secureAccountIds?.let { databaseAccountIds - it }?.toSortedJson().orNull()
                    )
                    .put(
                        "health",
                        makeOverallHealth(accountItems, inspectionErrors.length() > 0)
                    )
                    .put("items", JSONArray(accountItems.map { it.json }))
            )
            .put(
                "security",
                JSONObject()
                    .put("configuredAuthTypes", JSONArray(configuredAuthTypes))
                    .put("isLegacyMigrationAllowed", enclave?.isLegacyMigrationAllowed.orNull())
                    .put("isLegacyCleanupPending", enclave?.isLegacyCleanupPending.orNull())
                    .put(
                        "legacyCiphertextAccountIds",
                        secureInspection.legacyCiphertextAccountIds.toSortedJson()
                    )
                    .put(
                        "malformedLegacySecretAccountIds",
                        secureInspection.malformedLegacySecretAccountIds.toSortedJson()
                    )
                    .put(
                        "enclaveSecretAccountIds",
                        enclaveSecretAccountIds?.toSortedJson().orNull()
                    )
                    .put(
                        "missingEnclaveSecretAccountIds",
                        missingEnclaveSecretAccountIds?.toSortedJson().orNull()
                    )
                    .put("failedLoginAttempts", WSecureStorage.getFailedLoginAttempts().orNull())
                    .put("inspectionErrors", inspectionErrors)
            )
    }

    private fun makeAppInfo(context: Context): JSONObject {
        val packageInfo = ApplicationContextHolder.packageInfo
        val packageManager = context.packageManager
        val installer = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(context.packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(context.packageName)
            }
        } catch (_: Exception) {
            null
        }
        return JSONObject()
            .put("name", context.applicationInfo.loadLabel(packageManager).toString())
            .put("packageName", context.packageName)
            .put("version", packageInfo.versionName.orNull())
            .put("build", PackageInfoCompat.getLongVersionCode(packageInfo))
            .put("installerPackageName", installer.orNull())
            .put("isDebugBuild", DEBUG_MODE)
            .put(
                "webViewVersion",
                WebViewCompat.getCurrentWebViewPackage(context)?.versionName.orNull()
            )
    }

    private fun makeDeviceInfo(context: Context): JSONObject {
        val activityManager = context.getSystemService(ActivityManager::class.java)
        val memoryInfo = ActivityManager.MemoryInfo().also { activityManager?.getMemoryInfo(it) }
        val powerManager = context.getSystemService(PowerManager::class.java)
        val storage = try {
            StatFs(context.filesDir.path)
        } catch (_: Exception) {
            null
        }
        val metrics = context.resources.displayMetrics
        val display = context.getSystemService(DisplayManager::class.java)
            ?.getDisplay(Display.DEFAULT_DISPLAY)
        val thermalStatus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            powerManager?.currentThermalStatus?.let(::thermalStatusName)
        } else {
            null
        }
        val locales = context.resources.configuration.locales

        return JSONObject()
            .put("manufacturer", Build.MANUFACTURER)
            .put("model", Build.MODEL)
            .put("device", Build.DEVICE)
            .put("systemVersion", Build.VERSION.RELEASE)
            .put("sdkInt", Build.VERSION.SDK_INT)
            .put("localeIdentifier", Locale.getDefault().toLanguageTag())
            .put(
                "preferredLanguages",
                JSONArray((0 until locales.size()).map { locales[it].toLanguageTag() })
            )
            .put("timeZone", TimeZone.getDefault().id)
            .put("physicalMemoryBytes", memoryInfo.totalMem)
            .put("availableMemoryBytes", memoryInfo.availMem)
            .put("isLowRamDevice", activityManager?.isLowRamDevice.orNull())
            .put("availableStorageBytes", storage?.availableBytes.orNull())
            .put("totalStorageBytes", storage?.totalBytes.orNull())
            .put("isPowerSaveMode", powerManager?.isPowerSaveMode.orNull())
            .put("thermalStatus", thermalStatus.orNull())
            .put(
                "screen",
                JSONObject()
                    .put("widthPixels", metrics.widthPixels)
                    .put("heightPixels", metrics.heightPixels)
                    .put("density", metrics.density.toDouble())
                    .put("refreshRate", display?.refreshRate?.toDouble().orNull())
            )
    }

    private fun makeInstallationInfo(): JSONObject {
        val packageInfo = ApplicationContextHolder.packageInfo
        val processUptimeMillis = SystemClock.elapsedRealtime() - Process.getStartElapsedRealtime()
        return JSONObject()
            .put("firstInstallAt", formatDate(packageInfo.firstInstallTime))
            .put("lastUpdateAt", formatDate(packageInfo.lastUpdateTime))
            .put("processStartedAt", formatDate(System.currentTimeMillis() - processUptimeMillis))
            .put("processUptimeSeconds", processUptimeMillis / 1000.0)
            .put("clientId", installationValue("clientId") ?: secureValue("clientId"))
            .put("stateVersion", secureValue("stateVersion"))
            .put("secureStorageCurrentAccountId", secureValue("currentAccountId"))
            .put("baseCurrency", WGlobalStorage.getBaseCurrency())
            .put("secureStorageKeys", WSecureStorage.getKeys().toSet().toSortedJson())
    }

    private fun inspectSecureAccounts(): SecureAccountsInspection = try {
        val accountsData = WSecureStorage.allAccounts()
        val accounts = if (accountsData.isEmpty()) JSONObject() else JSONObject(accountsData)
        val legacyCiphertextAccountIds = mutableSetOf<String>()
        val malformedLegacySecretAccountIds = mutableSetOf<String>()
        for (accountId in accounts.keys()) {
            val account = accounts.optJSONObject(accountId)
            if (account == null) {
                malformedLegacySecretAccountIds.add(accountId)
                continue
            }
            if (!account.has("mnemonicEncrypted")) continue
            if ((account.opt("mnemonicEncrypted") as? String)?.isNotEmpty() == true) {
                legacyCiphertextAccountIds.add(accountId)
            } else {
                malformedLegacySecretAccountIds.add(accountId)
            }
        }
        SecureAccountsInspection(
            accountIds = accounts.keys().asSequence().toSet(),
            legacyCiphertextAccountIds = legacyCiphertextAccountIds,
            malformedLegacySecretAccountIds = malformedLegacySecretAccountIds,
            error = null
        )
    } catch (e: Exception) {
        SecureAccountsInspection(
            accountIds = null,
            legacyCiphertextAccountIds = emptySet(),
            malformedLegacySecretAccountIds = emptySet(),
            error = e.javaClass.name
        )
    }

    private fun makeAccountItems(
        databaseAccounts: Map<String, JSONObject?>,
        currentAccountId: String?,
        orderedAccountIds: List<String>,
        secureInspection: SecureAccountsInspection,
        hasConfiguredAuth: Boolean,
        enclaveSecretAccountIds: Set<String>?,
        isLegacyMigrationPending: Boolean
    ): List<AccountItem> {
        val orderByAccountId = orderedAccountIds.withIndex().associate { it.value to it.index }
        val allAccountIds = (
            databaseAccounts.keys + secureInspection.accountIds.orEmpty() +
                listOfNotNull(currentAccountId)
            ).toSortedSet()

        return allAccountIds.map { accountId ->
            val account = databaseAccounts[accountId]
            val isTemporary = accountId in WGlobalStorage.temporaryAddedAccountIds
            val isCurrent = accountId == currentAccountId
            val isEncrypted = account != null && isStoredEncrypted(account)
            val issues = buildList {
                if (account == null && isCurrent) add("missingDatabaseRecord")
                if (account != null && !isParsableAccount(accountId, account)) {
                    add("malformedDatabaseRecord")
                }
                if (account != null && !isTemporary && !isLegacyMigrationPending &&
                    secureInspection.accountIds?.contains(accountId) == false
                ) {
                    add("missingSecureStorageRecord")
                }
                if (accountId in secureInspection.malformedLegacySecretAccountIds) {
                    add("malformedLegacySecret")
                }
                if (isEncrypted && hasConfiguredAuth && enclaveSecretAccountIds != null &&
                    accountId !in enclaveSecretAccountIds
                ) {
                    add("missingEnclaveSecret")
                }
            }
            val status = when {
                account == null && issues.isEmpty() -> "legacyOnly"
                issues.isEmpty() -> "healthy"
                else -> "needsAttention"
            }
            val json = JSONObject()
                .put("id", accountId)
                .put("type", account?.optString("type")?.ifEmpty { null }.orNull())
                .put(
                    "chains",
                    account?.optJSONObject(
                        "byChain"
                    )?.keys()?.asSequence()?.toSet().orEmpty().toSortedJson()
                )
                .put("isTemporary", isTemporary)
                .put("isCurrent", isCurrent)
                .put("orderIndex", orderByAccountId[accountId].orNull())
                .put("existsInDatabase", account != null)
                .put(
                    "existsInSecureStorage",
                    secureInspection.accountIds?.contains(accountId).orNull()
                )
                .put("legacySecretState", legacySecretState(accountId, secureInspection))
                .put(
                    "enclaveSecretState",
                    when {
                        !isEncrypted -> "notApplicable"
                        !hasConfiguredAuth -> "notConfigured"
                        enclaveSecretAccountIds == null -> "unknown"
                        accountId in enclaveSecretAccountIds -> "present"
                        else -> "missing"
                    }
                )
                .put("health", makeHealth(status, issues))
            AccountItem(issues, json)
        }
    }

    private fun makeOverallHealth(
        items: List<AccountItem>,
        hasInspectionErrors: Boolean
    ): JSONObject {
        val issues = items.flatMap { it.issues }.toSortedSet()
        if (hasInspectionErrors) issues.add("inspectionIncomplete")
        val status = when {
            hasInspectionErrors -> "unknown"
            issues.isNotEmpty() -> "needsAttention"
            else -> "healthy"
        }
        return makeHealth(status, issues.toList())
    }

    private fun makeHealth(status: String, issues: List<String>): JSONObject = JSONObject()
        .put("status", status)
        .put("issues", JSONArray(issues))

    private fun legacySecretState(accountId: String, inspection: SecureAccountsInspection): String {
        val accountIds = inspection.accountIds ?: return "unknown"
        return when (accountId) {
            !in accountIds -> "accountNotInSecureStorage"
            in inspection.legacyCiphertextAccountIds -> "present"
            in inspection.malformedLegacySecretAccountIds -> "malformed"
            else -> "absent"
        }
    }

    private fun isParsableAccount(accountId: String, account: JSONObject): Boolean = try {
        MAccount(accountId, account)
        true
    } catch (_: Exception) {
        false
    }

    private fun isStoredEncrypted(account: JSONObject): Boolean = when (account.optString("type")) {
        MAccount.AccountType.HARDWARE.value, MAccount.AccountType.VIEW.value -> false
        else -> true
    }

    private fun installationValue(key: String): String? = WSdkInstallationStorage.getValue(key)

    private fun secureValue(key: String): Any = WSecureStorage.getSecValue(key).ifEmpty {
        null
    }.orNull()

    private fun thermalStatusName(status: Int): String = when (status) {
        PowerManager.THERMAL_STATUS_NONE -> "none"
        PowerManager.THERMAL_STATUS_LIGHT -> "light"
        PowerManager.THERMAL_STATUS_MODERATE -> "moderate"
        PowerManager.THERMAL_STATUS_SEVERE -> "severe"
        PowerManager.THERMAL_STATUS_CRITICAL -> "critical"
        PowerManager.THERMAL_STATUS_EMERGENCY -> "emergency"
        PowerManager.THERMAL_STATUS_SHUTDOWN -> "shutdown"
        else -> "unknown"
    }

    private fun formatDate(timestamp: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date(timestamp))

    private fun Any?.orNull(): Any = this ?: JSONObject.NULL

    private fun Set<String>.toSortedJson(): JSONArray = JSONArray(sorted())

    private class SecureAccountsInspection(
        val accountIds: Set<String>?,
        val legacyCiphertextAccountIds: Set<String>,
        val malformedLegacySecretAccountIds: Set<String>,
        val error: String?
    )

    private class AccountItem(val issues: List<String>, val json: JSONObject)
}
