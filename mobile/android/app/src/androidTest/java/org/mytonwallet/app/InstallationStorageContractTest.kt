package org.mytonwallet.app

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.installationStorage.InstallationFile
import org.mytonwallet.app_air.walletcontext.installationStorage.PlaySnapshot
import org.mytonwallet.app_air.walletcontext.installationStorage.SourceSnapshot
import org.mytonwallet.app_air.walletcontext.installationStorage.WalletAttributionMigration
import org.mytonwallet.app_air.walletcontext.sdkStorage.WSdkStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import java.io.File

@RunWith(AndroidJUnit4::class)
class InstallationStorageContractTest {
  private val context = InstrumentationRegistry.getInstrumentation().targetContext
  private val directory = File(context.noBackupFilesDir, "installation-contract")
  private val path get() = File(directory, "installation-v1.json")

  private fun journal(hook: (String) -> Unit = {}) = InstallationFile(directory, { 123L }, hook)

  @Before fun setup() {
    directory.deleteRecursively()
    assertTrue(directory.mkdirs())
  }

  @Test fun absenceRecoveryCorruptionAndOwnerLossStayDistinct() {
    var fail = true
    val owner = journal { if (fail && it == "writing") error("disk") }
    assertThrows(Exception::class.java) { owner.open() }
    fail = false
    assertTrue(owner.open())
    val original = owner.getPending().toString()
    android.util.AtomicFile(path).startWrite().apply {
      write("partial".toByteArray())
      close()
    }
    assertFalse(journal().open())
    assertTrue(path.renameTo(File("${path.path}.bak")))
    assertFalse(journal().open())
    val valid = path.readText()
    listOf(
      valid.dropLast(1),
      valid.replace(Regex("\"storageContract\":\\d+"), "\"storageContract\":1"),
      valid.replace("\"playInstalledAt\":null", "\"playInstalledAt\":\"0\""),
      valid.replaceFirst("\"latest\":{", "\"latest\":{\"unknown\":true,"),
      " $valid",
      "x".repeat(131073),
    ).forEach { corrupt ->
      path.writeText(corrupt)
      assertThrows(Exception::class.java) {
        InstallationFile(directory, { 123L }, randomId = { error("mint") }).open()
      }
      assertEquals(corrupt, path.readText())
    }
    path.delete()
    assertThrows(Exception::class.java) { owner.open() }
    assertFalse(path.exists())
    val reset = pending(journal().apply { open() }, "play").getJSONObject("body")
    val first = JSONArray(original).getJSONObject(0).getJSONObject("body")
    assertFalse(first.getString("installationId") == reset.getString("installationId"))
    path.delete()
    File("${path.path}.new").writeText("orphan")
    assertThrows(Exception::class.java) { journal().open() }
    File("${path.path}.new").delete()
    assertTrue(path.mkdir())
    assertThrows(Exception::class.java) { journal().open() }
  }

  @Test fun immutablePendingAcceptsOnlyExactAckAndEmitsLatestSuccessor() {
    var fail = false
    val storage = journal { if (fail && it == "writing") error("disk") }.apply { open() }
    val first = pending(storage, "play")
    storage.observe(PlaySnapshot(null, 1000, "1.0", "ok", utm("campaign")))
    assertFalse(storage.observe(PlaySnapshot(null, null, "", "service_unavailable", null)))
    val bytes = path.readText()
    assertEquals(first.toString(), pending(storage, "play").toString())
    val exact = ack(first)
    fail = true
    assertThrows(Exception::class.java) { storage.acknowledge("play", exact) }
    assertEquals(bytes, path.readText())
    fail = false
    listOf(
      JSONObject(exact.toString()).put("schemaVersion", "2"),
      JSONObject(exact.toString()).put("eventId", "00000000-0000-4000-8000-000000000099"),
      JSONObject(exact.toString()).put("installationId", "other"),
      JSONObject(exact.toString()).put("ok", "true"),
      JSONObject(exact.toString()).put("extra", true),
    ).forEach {
      assertFalse(storage.acknowledge("play", it))
    }
    assertEquals(bytes, path.readText())
    assertFalse(storage.acknowledge("deeplink", exact))
    assertTrue(storage.acknowledge("play", exact))
    val successor = pending(storage, "play")
    val body = successor.getJSONObject("body")
    assertEquals("ok", body.getString("collectionStatus"))
    assertEquals("campaign", body.getJSONObject("source").getString("channel"))
    assertFalse(body.getString("eventId") == exact.getString("eventId"))
    assertFalse(storage.acknowledge("play", exact))
    assertTrue(storage.acknowledge("play", ack(successor)))
    assertTrue(journal().hasSuccessfulObservation())
  }

  @Test fun latePackageDateAndFirstTouchCreateAtomicSuccessors() {
    var date: Long? = null
    val storage = InstallationFile(directory, { date }).apply { open() }
    storage.observe(PlaySnapshot(null, -9007199254740991L, "v".repeat(64), "ok", utm("play")))
    storage.acknowledge("play", ack(pending(storage, "play")))
    storage.acknowledge("play", ack(pending(storage, "play")))
    date = 9007199254740991L
    assertTrue(storage.open())
    val enriched = pending(storage, "play").getJSONObject("body")
    assertEquals(date, enriched.getLong("packageInstalledAt"))
    assertEquals(-9007199254740991L, enriched.getLong("playInstalledAt"))
    assertTrue(storage.selectDeeplink(SourceSnapshot("", "referrer", "external_referrer", "partner.example")))
    val first = pending(storage, "deeplink")
    assertTrue(storage.selectDeeplink(utm("winner")))
    assertFalse(storage.selectDeeplink(utm("later")))
    assertEquals(first.toString(), pending(storage, "deeplink").toString())
    storage.acknowledge("deeplink", ack(first))
    val winner = pending(storage, "deeplink").getJSONObject("body")
    assertEquals("winner", winner.getJSONObject("source").getString("channel"))
  }

  @Test fun walletClearCannotChangeInstallationRecord() {
    val storage = journal().apply { open() }
    ApplicationContextHolder.update(context.applicationContext)
    WSecureStorage.init(context)
    WSdkStorage.init(context)
    val clearOperations = listOf(WSecureStorage::deleteAllWalletValues, WSecureStorage::clearStorage)
    for (isAcknowledged in listOf(false, true)) {
      if (isAcknowledged) assertTrue(storage.acknowledge("play", ack(pending(storage, "play"))))
      val before = path.readText() to storage.getPending().toString()
      for (clearWallet in clearOperations) {
        for (key in listOf("clientId", "accounts", "mnemonicEncrypted", "installMetadata")) {
          WSecureStorage.setSecValue(key, "synthetic-wallet-data")
          WSdkStorage.setValue(key, "synthetic-sdk-data")
        }
        clearWallet()
        WSdkStorage.clearStorage()
        WSecureStorage.clearCache()
        for (key in listOf("clientId", "accounts", "mnemonicEncrypted", "installMetadata")) {
          assertEquals("", WSecureStorage.getSecValue(key))
          assertEquals("", WSdkStorage.getValue(key))
        }
        val reopened = journal().apply { open() }
        assertEquals(before, path.readText() to reopened.getPending().toString())
      }
    }
  }

  @Test fun walletSourceRetainsFirstTransportAcrossInstallationAcknowledgements() {
    val storage = journal().apply { open() }
    storage.selectDeeplink(utm("deeplink_first"))
    storage.observe(PlaySnapshot(null, 1000, "1.0", "ok", utm("play_later")))
    while (storage.getPending().length() > 0) {
      val delivery = storage.getPending().getJSONObject(0)
      assertTrue(storage.acknowledge(delivery.getString("slot"), ack(delivery)))
    }
    journal().open()
    val record = JSONObject(path.readText())
    assertTrue("The selected wallet source must survive all V2 ACKs", record.has("walletAttribution"))
    assertEquals(
      "deeplink_first",
      record.getJSONObject("walletAttribution").getJSONObject("source").getString("channel"),
    )
    assertEquals(0, storage.getPending().length())
  }

  @Test fun walletMigrationUsesSavedSourceThenLegacyPendingThenOrderedCaptures() {
    val cases =
      listOf(
        Triple(source("saved"), source("legacy_pending"), "saved"),
        Triple(referrer("saved.example"), source("legacy_pending"), "legacy_pending"),
        Triple(referrer("saved.example"), referrer("pending.example"), "captured"),
        Triple(null, source("legacy_pending"), "legacy_pending"),
        Triple(null, null, "captured"),
      )
    for ((seed, pending, expected) in cases) {
      directory.deleteRecursively()
      assertTrue(directory.mkdirs())
      val storage = journal().apply { open() }
      storage.selectDeeplink(utm("captured"))
      storage.observe(PlaySnapshot(null, 1000, "1.0", "ok", utm("later_play")))
      val before = storage.getPending().toString()
      val projection = storage.syncWalletAttribution(seed, pending)
      assertEquals(expected, projection.getJSONObject("source").getString("channel"))
      assertFalse(projection.getJSONObject("source").has("sourceOutcome"))
      assertEquals(before, storage.getPending().toString())
      assertEquals(projection.toString(), journal().syncWalletAttribution(source("later_seed")).toString())
    }
    directory.deleteRecursively()
    assertTrue(directory.mkdirs())
    val storage = journal().apply { open() }
    storage.observe(PlaySnapshot(null, 1000, "1.0", "ok", utm("play_first")))
    storage.selectDeeplink(utm("deeplink_later"))
    assertEquals("play_first", storage.syncWalletAttribution(null).getJSONObject("source").getString("channel"))
  }

  @Test fun legacyClaimsKeepTheirEnvelopeAndTechnicalClaimsStaySeparate() {
    val storage = journal().apply { open() }
    val legacy = JSONObject(source("x".repeat(64))).put("legacy", true).toString()
    val before = storage.getPending().toString()
    val selected = storage.syncWalletAttribution(legacy).getJSONObject("source")
    assertEquals("x".repeat(64), selected.getString("channel"))
    assertTrue(selected.getBoolean("legacy"))
    assertEquals(before, storage.getPending().toString())
    storage.selectDeeplink(utm("later"))
    assertEquals(selected.toString(), storage.syncWalletAttribution(null).getJSONObject("source").toString())
    for (status in listOf(
      "pending",
      "service_unavailable",
      "connection_exception",
      "feature_not_supported",
      "developer_error",
      "unexpected_response",
    )) {
      storage.observe(PlaySnapshot(null, null, "", status, null))
      val projection = storage.syncWalletAttribution(null)
      if (status in setOf("feature_not_supported", "developer_error", "unexpected_response")) {
        assertEquals("direct", projection.getString("technicalKind"))
      } else {
        assertTrue(projection.isNull("technicalKind"))
      }
      assertEquals(selected.toString(), projection.getJSONObject("source").toString())
    }
    val installedAt = System.currentTimeMillis()
    storage.observe(PlaySnapshot(null, installedAt, "1.0", "ok", SourceSnapshot("", "referral", "referral")))
    val technical = storage.syncWalletAttribution(null)
    assertEquals("referral", technical.getString("technicalKind"))
    assertEquals("referral", technical.getString("sourceOutcome"))
    assertEquals(installedAt, technical.getLong("playInstalledAt"))
  }

  @Test fun technicalClaimCarriesCollectionTimeAndInstallerOutcome() {
    var isPlay: Boolean? = true
    val installedAt = 1_760_000_000_000L
    var clock = installedAt + 1000
    val storage = InstallationFile(directory, { 123L }, now = { clock }, isPlayInstall = { isPlay }).apply { open() }
    storage.observe(PlaySnapshot(null, installedAt, "1.0", "ok", SourceSnapshot("", "direct", "organic")))
    val latest = JSONObject(path.readText()).getJSONObject("play").getJSONObject("latest")
    assertEquals(installedAt + 1000, latest.getLong("collectedAt"))
    clock = installedAt + 91L * 24 * 60 * 60 * 1000
    assertEquals("organic", storage.syncWalletAttribution(null).getString("sourceOutcome"))
    isPlay = false
    val sideloaded = storage.syncWalletAttribution(null)
    assertEquals("direct", sideloaded.getString("technicalKind"))
    assertEquals("not_play_install", sideloaded.getString("sourceOutcome"))
    assertEquals(JSONObject(path.readText()).getString("installationId"), sideloaded.getString("installationId"))
  }

  @Test fun migrationCommitFailureRetainsLegacyPendingAndAcknowledgedInstallationEvents() {
    val preferences = context.getSharedPreferences("installAttribution", 0)
    preferences
      .edit()
      .clear()
      .putString("pending", source("legacy_pending"))
      .commit()
    var fail = false
    val storage = journal { if (fail && it == "writing") error("disk") }.apply { open() }
    assertTrue(storage.acknowledge("play", ack(pending(storage, "play"))))
    val before = path.readText()
    fail = true
    assertThrows(Exception::class.java) {
      WalletAttributionMigration.synchronize(context, null, storage::syncWalletAttribution)
    }
    assertEquals(before, path.readText())
    assertTrue(preferences.contains("pending"))
    fail = false
    val selected = WalletAttributionMigration.synchronize(context, null, storage::syncWalletAttribution)
    assertEquals("legacy_pending", selected.getJSONObject("source").getString("channel"))
    assertFalse(preferences.contains("pending"))
    assertEquals(0, storage.getPending().length())
  }

  @Test fun bothWalletClearOrdersDurablyCaptureTheOriginalSdkSourceBeforeDeletion() {
    ApplicationContextHolder.update(context.applicationContext)
    WSecureStorage.init(context)
    WSdkStorage.init(context)
    val preferences = context.getSharedPreferences("installAttribution", 0)
    for (secureFirst in listOf(true, false)) {
      directory.deleteRecursively()
      assertTrue(directory.mkdirs())
      preferences.edit().clear().commit()
      WSecureStorage.setSecValue("installAttribution", source("stale_secure"))
      WSdkStorage.setValue("installAttribution", source("accepted_sdk"))
      WSecureStorage.setSecValue("mnemonicEncrypted", "secret")
      WSdkStorage.setValue("clientId", "old_client")
      if (secureFirst) {
        WSecureStorage.deleteAllWalletValues()
        WSdkStorage.clearStorage()
      } else {
        WSdkStorage.clearStorage()
        WSecureStorage.clearStorage()
      }
      assertEquals("", WSecureStorage.getSecValue("mnemonicEncrypted"))
      assertEquals("", WSdkStorage.getValue("clientId"))
      assertEquals("accepted_sdk", JSONObject(preferences.getString("walletSourceBeforeClear", "")!!).getString("channel"))
      val storage = journal().apply { open() }
      val before = storage.getPending().toString()
      val result = WalletAttributionMigration.synchronize(context, source("new_client"), storage::syncWalletAttribution)
      assertEquals("accepted_sdk", result.getJSONObject("source").getString("channel"))
      assertEquals(before, storage.getPending().toString())
      assertFalse(preferences.contains("walletSourceBeforeClear"))
      WSdkStorage.setValue("installAttribution", source("later_reset"))
      WSdkStorage.clearStorage()
      assertFalse(preferences.contains("walletSourceBeforeClear"))
      assertEquals(result.toString(), journal().syncWalletAttribution(null).toString())
    }

    directory.deleteRecursively()
    assertTrue(directory.mkdirs())
    preferences.edit().clear().commit()
    val legacyChannel = "x".repeat(64)
    WSdkStorage.setValue("installAttribution", "")
    WSdkStorage.setValue("attributionChannel", JSONObject.quote(legacyChannel))
    WSdkStorage.clearStorage()
    WSecureStorage.clearStorage()
    val legacyStorage = journal().apply { open() }
    val before = legacyStorage.getPending().toString()
    val legacy =
      WalletAttributionMigration
        .synchronize(context, null, legacyStorage::syncWalletAttribution)
        .getJSONObject("source")
    assertEquals(legacyChannel, legacy.getString("channel"))
    assertTrue(legacy.getBoolean("legacy"))
    assertEquals(setOf("channel", "attributionKind", "legacy"), legacy.keys().asSequence().toSet())
    assertEquals(before, legacyStorage.getPending().toString())
  }

  @Test fun sdkTombstonesSuppressSecureFallbackAndCaptureFailuresNeverBlockSecretErasure() {
    ApplicationContextHolder.update(context.applicationContext)
    WSecureStorage.init(context)
    WSdkStorage.init(context)
    val preferences = context.getSharedPreferences("installAttribution", 0)
    preferences.edit().clear().commit()
    WSecureStorage.setSecValue("installAttribution", source("stale_secure"))
    WSecureStorage.setSecValue("attributionChannel", "\"old_legacy\"")
    WSdkStorage.setValue("installAttribution", "")
    WSdkStorage.setValue("attributionChannel", "")
    WSdkStorage.clearStorage()
    WSecureStorage.clearStorage()
    assertEquals("null", preferences.getString("walletSourceBeforeClear", null))
    val storage = journal().apply { open() }
    assertTrue(WalletAttributionMigration.synchronize(context, source("post_reset"), storage::syncWalletAttribution).isNull("source"))

    preferences.edit().clear().commit()
    WSdkStorage.setValue("installAttribution", "invalid-json")
    WSecureStorage.setSecValue("mnemonicEncrypted", "secret")
    path.writeText("broken installation journal")
    WSecureStorage.deleteAllWalletValues()
    WSdkStorage.clearStorage()
    assertEquals("", WSecureStorage.getSecValue("mnemonicEncrypted"))
    assertEquals("", WSdkStorage.getValue("installAttribution"))
    assertThrows(Exception::class.java) { journal().open() }
  }

  @Test fun malformedSdkSourceCannotResurrectSecureAttributionDuringSdkFirstClear() {
    ApplicationContextHolder.update(context.applicationContext)
    WSecureStorage.init(context)
    WSdkStorage.init(context)
    val preferences = context.getSharedPreferences("installAttribution", 0)
    preferences.edit().clear().commit()
    WSecureStorage.setSecValue("installAttribution", source("stale_secure"))
    WSecureStorage.setSecValue("mnemonicEncrypted", "secret")
    WSdkStorage.setValue("installAttribution", "invalid-json")
    WSdkStorage.setValue("attributionChannel", "\"must_not_fallback\"")
    WSdkStorage.clearStorage()
    WSecureStorage.clearStorage()
    assertEquals("", WSecureStorage.getSecValue("mnemonicEncrypted"))
    assertEquals("null", preferences.getString("walletSourceBeforeClear", null))
    val storage = journal().apply { open() }
    assertTrue(WalletAttributionMigration.synchronize(context, null, storage::syncWalletAttribution).isNull("source"))
  }

  @Test fun clearBeforeMigrationKeepsTheLegacyClaimEnvelope() {
    ApplicationContextHolder.update(context.applicationContext)
    WSecureStorage.init(context)
    WSdkStorage.init(context)
    val preferences = context.getSharedPreferences("installAttribution", 0)
    preferences.edit().clear().commit()
    val channel = "legacy_channel_longer_than_thirty_chars"
    WSdkStorage.setValue(
      "installAttribution",
      JSONObject()
        .put("channel", channel)
        .put("attributionKind", "utm")
        .put("legacy", true)
        .toString(),
    )
    WSdkStorage.clearStorage()
    val seed = JSONObject(preferences.getString("walletSourceBeforeClear", null)!!)
    assertEquals(channel, seed.getString("channel"))
    assertTrue(seed.getBoolean("legacy"))
    val storage = journal().apply { open() }
    val source =
      WalletAttributionMigration
        .synchronize(context, null, storage::syncWalletAttribution)
        .getJSONObject("source")
    assertEquals(channel, source.getString("channel"))
    assertTrue(source.getBoolean("legacy"))
  }

  private fun source(channel: String) = JSONObject().put("channel", channel).put("attributionKind", "utm").toString()

  private fun referrer(domain: String) =
    JSONObject()
      .put("channel", "")
      .put("attributionKind", "referrer")
      .put("referrerDomain", domain)
      .toString()

  private fun utm(channel: String) = SourceSnapshot(channel, "utm", "utm")

  private fun pending(
    store: InstallationFile,
    slot: String,
  ) = store.getPending().let { values ->
    (0 until values.length()).map(values::getJSONObject).first { it.getString("slot") == slot }
  }

  private fun ack(value: JSONObject) =
    JSONObject()
      .put("ok", true)
      .put("schemaVersion", 2)
      .put("eventId", value.getJSONObject("body").getString("eventId"))
      .put("installationId", value.getJSONObject("body").getString("installationId"))
}
