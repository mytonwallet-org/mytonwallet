package org.mytonwallet.app_air.walletcontext.installationStorage

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonClass
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.Moshi
import java.io.File
import java.lang.reflect.Type
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

private val uuid = Regex(
    "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}"
)
private val sourceOutcomes = mapOf(
    "utm" to "utm",
    "external_referrer" to "referrer",
    "organic" to "direct",
    "empty_referrer" to "direct",
    "missing_source" to "direct",
    "invalid_source" to "direct",
    "referral" to "referral"
)
private val finalCollectionFailures =
    setOf("feature_not_supported", "developer_error", "unexpected_response")
const val PLAY_REFERRER_TTL_MS = 90L * 24 * 60 * 60 * 1000
private const val PLAY_STORE_INSTALLER = "com.android.vending"

private fun safeDate(value: Long?) =
    require(value == null || value in -9007199254740991L..9007199254740991L)

@JsonClass(generateAdapter = true)
data class PlaySnapshot(
    val packageInstalledAt: Long?,
    val playInstalledAt: Long?,
    val installVersion: String,
    val collectionStatus: String,
    val source: SourceSnapshot?,
    val collectedAt: Long? = null
) {
    init {
        safeDate(packageInstalledAt)
        safeDate(playInstalledAt)
        safeDate(collectedAt)
        require(installVersion.length <= 64)
        require(
            collectionStatus in setOf(
                "pending",
                "ok",
                "service_unavailable",
                "service_disconnected",
                "feature_not_supported",
                "developer_error",
                "connection_exception",
                "read_exception",
                "unexpected_response"
            )
        )
        require((collectionStatus == "ok") == (source != null))
        require(
            collectionStatus == "ok" ||
                (playInstalledAt == null && installVersion.isEmpty() && collectedAt == null)
        )
    }
}

fun resolveTechnicalPlayOutcome(play: PlaySnapshot, isPlayInstall: Boolean?, now: Long): String? {
    val answer = play.source?.sourceOutcome
    val outcome = when {
        answer != null -> answer.takeIf { sourceOutcomes[it] in setOf("direct", "referral") }
        play.collectionStatus in finalCollectionFailures -> "play_unavailable"
        else -> null
    } ?: return null
    if (isPlayInstall == false) return "not_play_install"
    if (outcome == "play_unavailable") return outcome
    // An unstamped answer is aged by the read time, which can only overstate its age
    val installedAt = play.playInstalledAt ?: play.packageInstalledAt ?: return outcome
    val age = (play.collectedAt ?: now) - installedAt
    return if (age > PLAY_REFERRER_TTL_MS) "stale_referrer" else outcome
}

@JsonClass(generateAdapter = true)
data class SourceSnapshot(
    val channel: String,
    val attributionKind: String,
    val sourceOutcome: String,
    val referrerDomain: String? = null,
    val utmMedium: String? = null,
    val utmCampaign: String? = null,
    val utmContent: String? = null
) {
    init {
        require(sourceOutcomes[sourceOutcome] == attributionKind)
        require(
            if (attributionKind ==
                "utm"
            ) {
                Regex("[a-z0-9_]{1,30}").matches(channel)
            } else {
                channel == ""
            }
        )
        listOf(utmMedium, utmCampaign, utmContent).filterNotNull().forEach {
            require(
                attributionKind == "utm" && it.isNotEmpty() && it == it.trim() &&
                    it.toByteArray().size <= 128 && it.none { char ->
                        char.code in 0..31 || char.code in 127..159
                    }
            )
        }
        if (attributionKind == "referrer") {
            val domain = requireNotNull(referrerDomain)
            require(
                domain.length <= 253 && Regex(
                    "(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?"
                ).matches(domain)
            )
            require(
                listOf(
                    "mywallet.io",
                    "mytonwallet.io",
                    "mytonwallet.org",
                    "mytonwallet.app",
                    "my.tt",
                    "gramwallet.io",
                    "gramwallet.app"
                ).none { domain == it || domain.endsWith(".$it") }
            )
        } else {
            require(referrerDomain.isNullOrEmpty())
        }
    }
}

private val sourceAdapter = storageMoshi.adapter(SourceSnapshot::class.java).failOnUnknown()

fun selectInstallSource(previous: SourceSnapshot?, candidate: SourceSnapshot): SourceSnapshot =
    if (previous?.attributionKind != "utm" &&
        (previous?.attributionKind != "referrer" || candidate.attributionKind == "utm")
    ) {
        candidate
    } else {
        requireNotNull(previous)
    }

@JsonClass(generateAdapter = true)
data class DeeplinkSnapshot(val packageInstalledAt: Long?, val source: SourceSnapshot) {
    init {
        safeDate(packageInstalledAt)
        require(source.attributionKind in setOf("utm", "referrer"))
    }
}

@JsonClass(generateAdapter = true)
data class Pending<T>(val eventId: String, val snapshot: T) {
    init {
        require(uuid.matches(eventId))
    }
}

@JsonClass(generateAdapter = true)
data class Slot<T>(val latest: T, val pending: Pending<T>?)

@JsonClass(generateAdapter = true)
data class InstallationRecord(
    val storageContract: Int,
    val installationId: String,
    val play: Slot<PlaySnapshot>,
    val deeplink: Slot<DeeplinkSnapshot>?,
    val walletAttribution: WalletAttributionProjection
) {
    init {
        require(storageContract == 2 && uuid.matches(installationId))
    }
}

// Fields added after records were first written keep null as an absent key, the only form older
// writers produced, so their records stay canonical
private val fieldsAbsentWhenNull = mapOf<Type, Set<String>>(
    PlaySnapshot::class.java to setOf("collectedAt")
)

private object AbsentWhenNullFields : JsonAdapter.Factory {
    override fun create(type: Type, annotations: Set<Annotation>, moshi: Moshi): JsonAdapter<*>? {
        val fields = fieldsAbsentWhenNull[type] ?: return null
        val delegate = moshi.nextAdapter<Any>(this, type, annotations).serializeNulls()
        return object : JsonAdapter<Any>() {
            override fun fromJson(reader: JsonReader): Any? = delegate.fromJson(reader)

            override fun toJson(writer: JsonWriter, value: Any?) {
                val tree = delegate.toJsonValue(value)

                @Suppress("UNCHECKED_CAST")
                (tree as? MutableMap<String, Any?>)?.let { members ->
                    members.keys.removeAll { it in fields && members[it] == null }
                }
                writer.jsonValue(tree)
            }
        }
    }
}

internal val installationRecordAdapter = storageMoshi.newBuilder()
    .add(AbsentWhenNullFields)
    .build()
    .adapter(InstallationRecord::class.java)
    .serializeNulls()
    .failOnUnknown()

class InstallationFile(
    directory: File,
    private val packageDate: () -> Long?,
    checkpoint: (String) -> Unit = {},
    private val randomId: () -> String = { UUID.randomUUID().toString() },
    private val now: () -> Long = System::currentTimeMillis,
    private val isPlayInstall: () -> Boolean? = { null }
) {
    private val file = AtomicJsonFile(
        directory,
        "installation-v1.json",
        installationRecordAdapter,
        131072,
        checkpoint
    )
    private var establishedId: String? = null
    private var canCreate = true

    fun open(): Boolean {
        var changed = false
        if (!file.exists()) {
            check(canCreate) { "Installation record disappeared" }
            val initial = PlaySnapshot(packageDate(), null, "", "pending", null)
            file.write(
                InstallationRecord(
                    2,
                    randomId(),
                    Slot(initial, Pending(randomId(), initial)),
                    null,
                    WalletAttributionProjection(false, null)
                )
            )
            changed = true
        }
        canCreate = false
        val state = read()
        establishedId = state.installationId
        val date = packageDate()
        if (state.play.latest.packageInstalledAt == null && date != null) {
            file.write(
                state.copy(
                    play = state.play.withLatest(state.play.latest.copy(packageInstalledAt = date))
                )
            )
            changed = true
        }
        return changed
    }

    fun getPending(): JSONArray {
        val state = read()
        return JSONArray().apply {
            fun add(slot: String, eventId: String, date: Long?, snapshot: JSONObject) {
                val transport = if (slot == "play") "play_referrer" else "deeplink"
                val body = snapshot
                    .put("schemaVersion", 2)
                    .put("installationId", state.installationId)
                    .put("eventId", eventId)
                    .put("packageInstalledAt", date ?: JSONObject.NULL)
                    .put("sourceTransport", transport)
                put(JSONObject().put("slot", slot).put("body", body))
            }
            state.play.pending?.let { pending ->
                val snapshot = pending.snapshot
                add(
                    "play",
                    pending.eventId,
                    snapshot.packageInstalledAt,
                    JSONObject()
                        .put("playInstalledAt", snapshot.playInstalledAt ?: JSONObject.NULL)
                        .put(
                            "installVersion",
                            snapshot.installVersion
                        ).put("collectionStatus", snapshot.collectionStatus)
                        .put("source", snapshot.source?.json() ?: JSONObject.NULL)
                )
            }
            state.deeplink?.pending?.let {
                add(
                    "deeplink",
                    it.eventId,
                    it.snapshot.packageInstalledAt,
                    JSONObject().put("source", it.snapshot.source.json())
                )
            }
        }
    }

    fun acknowledge(slot: String, response: JSONObject): Boolean {
        if (response.keys().asSequence().toSet() !=
            setOf("ok", "schemaVersion", "eventId", "installationId") ||
            response.opt("ok") != true || response.opt("schemaVersion") != 2 ||
            response.opt("eventId") !is String || response.opt("installationId") !is String
        ) {
            return false
        }
        val state = read()
        if (response.getString("installationId") != state.installationId) return false
        val eventId = response.getString("eventId")
        val next = when (slot) {
            "play" -> state.copy(play = state.play.acknowledge(eventId) ?: return false)

            "deeplink" -> state.copy(
                deeplink = state.deeplink?.acknowledge(eventId) ?: return false
            )

            else -> return false
        }
        file.write(next)
        return true
    }

    fun observe(snapshot: PlaySnapshot): Boolean {
        val state = read()
        if (state.play.latest.collectionStatus == "ok") return false
        val latest = snapshot.copy(
            packageInstalledAt =
                state.play.latest.packageInstalledAt ?: packageDate(),
            collectedAt = now().takeIf { snapshot.collectionStatus == "ok" }
        )
        val next = state.copy(
            play = state.play.withLatest(latest),
            walletAttribution = state.walletAttribution.capture(latest.source?.walletSource())
        )
        if (next == state) return false
        file.write(next)
        return true
    }

    fun selectDeeplink(source: SourceSnapshot): Boolean {
        require(source.attributionKind in setOf("utm", "referrer"))
        val state = read()
        val previous = state.deeplink?.latest
        val selected = selectInstallSource(previous?.source, source)
        val latest =
            DeeplinkSnapshot(
                previous?.packageInstalledAt ?: state.play.latest.packageInstalledAt,
                selected
            )
        val next = state.copy(
            deeplink =
                state.deeplink?.withLatest(latest) ?: Slot(latest, Pending(randomId(), latest)),
            walletAttribution = state.walletAttribution.capture(source.walletSource())
        )
        if (next == state) return false
        file.write(next)
        return true
    }

    fun hasSuccessfulObservation() = read().play.latest.collectionStatus == "ok"

    fun syncWalletAttribution(seed: String?, legacyPending: String? = null): JSONObject {
        val state = read()
        val candidate = parseWalletAttributionSource(seed)
        val pending = runCatching {
            legacyPending?.let(attributionValueAdapter::fromJson)?.let(::normalizeSavedWalletSource)
        }.getOrNull()
        val selected = state.walletAttribution.initialize(candidate, pending)
        if (selected !=
            state.walletAttribution
        ) {
            file.write(state.copy(walletAttribution = selected))
        }
        val play = state.play.latest
        val outcome = resolveTechnicalPlayOutcome(play, isPlayInstall(), now())
        return JSONObject()
            .put("source", selected.source?.json() ?: JSONObject.NULL)
            .put(
                "technicalKind",
                outcome?.let { if (it == "referral") "referral" else "direct" } ?: JSONObject.NULL
            )
            .put("sourceOutcome", outcome ?: JSONObject.NULL)
            .put("playInstalledAt", play.playInstalledAt ?: JSONObject.NULL)
            .put("installationId", state.installationId)
    }

    private fun read() = file.read().also {
        check(establishedId == null || establishedId == it.installationId) {
            "Installation record changed"
        }
    }
    private fun <T> Slot<T>.withLatest(value: T) =
        Slot(value, pending ?: if (latest != value) Pending(randomId(), value) else null)
    private fun <T> Slot<T>.acknowledge(eventId: String): Slot<T>? {
        val current = pending?.takeIf { it.eventId == eventId } ?: return null
        return copy(pending = if (current.snapshot == latest) null else Pending(randomId(), latest))
    }
    private fun SourceSnapshot.json() = JSONObject(sourceAdapter.toJson(this))
}

object WInstallationStorage {
    private val worker = boundedSerialWorker("InstallationStorage")
    private val admissionRetry by lazy { Handler(Looper.getMainLooper()) }
    private var store: InstallationFile? = null
    private var isOpened = false
    private var pending: SourceSnapshot? = null
    private var pendingContext: Context? = null
    private var pendingCallback: (() -> Unit)? = null
    private val retryAdmission = Runnable { admitPending() }
    private var flushRetryDelay = 500L

    fun enqueue(operation: () -> Unit) = worker.accept {
        try {
            operation()
        } finally {
            if (runCatching(::flushPending).isSuccess) {
                flushRetryDelay = 500L
            } else {
                scheduleAdmission(flushRetryDelay)
                flushRetryDelay = minOf(flushRetryDelay * 2, 60_000L)
            }
        }
    }

    private fun scheduleAdmission(delay: Long) {
        admissionRetry.removeCallbacks(retryAdmission)
        admissionRetry.postDelayed(retryAdmission, delay)
    }

    fun ensureOpen(context: Context) = open(context.applicationContext).let { flushPending() || it }

    private fun open(context: Context): Boolean {
        val current = store ?: InstallationFile(
            context.noBackupFilesDir,
            {
                runCatching {
                    context.packageManager.getPackageInfo(context.packageName, 0).firstInstallTime
                }.getOrNull()
            },
            isPlayInstall = { getInstallerPackage(context)?.let { it == PLAY_STORE_INSTALLER } }
        ).also { store = it }
        isOpened = false
        val changed = current.open()
        isOpened = true
        return changed
    }

    private fun getInstallerPackage(context: Context): String? {
        val manager = context.packageManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            runCatching { manager.getInstallSourceInfo(context.packageName) }.getOrNull()?.let {
                listOf(it.installingPackageName, it.initiatingPackageName)
                    .firstOrNull { name -> !name.isNullOrEmpty() }
                    ?.let { name -> return name }
            }
        }
        @Suppress("DEPRECATION")
        return runCatching { manager.getInstallerPackageName(context.packageName) }
            .getOrNull()
            ?.takeIf { it.isNotEmpty() }
    }

    @Synchronized
    fun captureSource(context: Context, source: SourceSnapshot, onCommitted: () -> Unit = {}) {
        pending = selectInstallSource(pending, source)
        pendingContext = context.applicationContext
        pendingCallback = onCommitted
        admitPending()
    }

    private fun admitPending() {
        if (synchronized(this) { pending } != null && !enqueue {}) {
            scheduleAdmission(500)
        }
    }

    private fun flushPending(): Boolean {
        val source = synchronized(this) { pending } ?: return false
        if (!isOpened) open(checkNotNull(synchronized(this) { pendingContext }))
        val changed = checkNotNull(store).selectDeeplink(source)
        val callback = synchronized(this) {
            if (pending != source) return@synchronized null
            pending = null
            pendingCallback.also { pendingCallback = null }
        }
        if (changed) callback?.invoke()
        return changed
    }

    fun observe(snapshot: PlaySnapshot) = checkNotNull(store).observe(snapshot)
    fun getPending() = checkNotNull(store).getPending()
    fun acknowledge(slot: String, response: JSONObject) =
        checkNotNull(store).acknowledge(slot, response)
    fun hasSuccessfulObservation() = isOpened && checkNotNull(store).hasSuccessfulObservation()

    fun syncWalletAttribution(context: Context, seed: String?) =
        WalletAttributionMigration.synchronize(
            context,
            seed,
            checkNotNull(store)::syncWalletAttribution
        )
}
