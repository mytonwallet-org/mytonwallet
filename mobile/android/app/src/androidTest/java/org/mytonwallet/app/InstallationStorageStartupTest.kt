package org.mytonwallet.app

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcontext.installationStorage.PlaySnapshot
import org.mytonwallet.app_air.walletcontext.installationStorage.SourceSnapshot
import org.mytonwallet.app_air.walletcontext.installationStorage.WInstallationStorage
import org.mytonwallet.app_air.walletcore.InstallReferrerChannel
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.splitAttributionDeeplink
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class InstallationStorageStartupTest {
  private val instrumentation = InstrumentationRegistry.getInstrumentation()
  private val context = instrumentation.targetContext

  @Test
  fun saturatedWorkerPersistsColdCaptureBeforeNativeBridgeDelivery() {
    val (release, drained) = saturateWorker()
    val committed = CountDownLatch(1)
    WInstallationStorage.captureSource(context, SourceSnapshot("admitted", "utm", "utm")) { committed.countDown() }
    release.countDown()
    assertTrue(committed.await(5, TimeUnit.SECONDS))
    assertTrue(drained.await(5, TimeUnit.SECONDS))
    val journal = File(context.noBackupFilesDir, "installation-v1.json")
    val stored = JSONObject(journal.readText())
    val source = stored.getJSONObject("deeplink").getJSONObject("latest").getJSONObject("source")
    assertEquals("admitted", source.getString("channel"))
    val startupRelease = saturateWorker().first
    try {
      startWallet()
      instrumentation.runOnMainSync {}
      assertEquals("pending", playStatus(journal))
    } finally {
      startupRelease.countDown()
    }
    await("Play collection was not retried") { playStatus(journal) != "pending" }
    val successful = PlaySnapshot(null, 1, "seeded", "ok", SourceSnapshot("seeded", "utm", "utm"))
    assertTrue(WInstallationStorage.enqueue { WInstallationStorage.observe(successful) })

    val result =
      runSdk(
        """
            const deliveries = (await nativeCall('airInstallationGetPending')).result;
            const play = deliveries.find(item => item.slot === 'play').body;
            const deeplink = deliveries.find(item => item.slot === 'deeplink').body;
            const ack = await nativeCall('airInstallationAcknowledge', 'play', JSON.stringify({
              ok: true, schemaVersion: 2, eventId: play.eventId, installationId: play.installationId
            }));
            const unsupported = await nativeCall('airInstallationSelectDeeplink', JSON.stringify({
              channel: 'forged', attributionKind: 'utm'
            }));
            const pending = (await nativeCall('airInstallationGetPending')).result.find(item => item.slot === 'play').body;
            const wallet = (await nativeCall('airInstallationSyncWalletAttribution', 'null')).result;
            return { deeplink, ack, unsupported, pending, wallet };
        """,
      )
    assertEquals("admitted", result.getJSONObject("deeplink").getJSONObject("source").getString("channel"))
    assertTrue(result.getJSONObject("ack").getBoolean("result"))
    assertFalse(result.getJSONObject("unsupported").getBoolean("ok"))
    assertEquals("ok", result.getJSONObject("pending").getString("collectionStatus"))
    assertEquals("admitted", result.getJSONObject("wallet").getJSONObject("source").getString("channel"))

    val reopened = CompletableFuture<Boolean>()
    assertTrue(WInstallationStorage.enqueue { reopened.complete(WInstallationStorage.ensureOpen(context)) })
    assertFalse(reopened.get(5, TimeUnit.SECONDS))
    val wakeRelease = blockWorker()
    try {
      runSdk(
        """
            const callbacks = window.airBridge.nativeCallCallbacks, android = window.androidApp;
            const state = window.installationWakeProbe = { reads: [] };
            window.androidApp = { nativeCall(...args) {
              const [id, method] = args;
              if (method === 'airInstallationGetPending') state.reads.push(id);
              if (method === 'airInstallationGetPending' && state.reads.length > 1) return;
              android.nativeCall(...args);
            }};
            window.airBridge.handleInstallationStateChange();
            while (state.reads.length === 0) await new Promise(resolve => setTimeout(resolve, 100));
            if (!callbacks[state.reads[0]]) throw new Error('Installation read was not admitted');
            while (callbacks[state.reads[0]]) await new Promise(resolve => setTimeout(resolve, 100));
            return state;
        """,
      )
      assertTrue(InstallReferrerChannel.deliver(context, requireNotNull(WalletCore.bridge)))
    } finally {
      wakeRelease.countDown()
    }
    await("Registration did not start a fresh installation read") {
      runSdk("return window.installationWakeProbe;").getJSONArray("reads").length() == 2
    }
    val reads = runSdk("return window.installationWakeProbe;").getJSONArray("reads")
    assertTrue(reads.getInt(0) > 0 && reads.getInt(1) > 0 && reads.getInt(0) != reads.getInt(1))
  }

  @Test
  fun sdkReachesInstallationStorageThroughTheRealBridge() {
    startWallet()
    val journal = File(context.noBackupFilesDir, "installation-v1.json")
    await("The SDK never synchronized wallet attribution through the native bridge") {
      journal.exists() &&
        JSONObject(journal.readText()).getJSONObject("walletAttribution").getBoolean("initialized")
    }
  }

  @Test
  fun corruptJournalAndColdStartCaptureDoNotBlockActivityOrWallet() =
    runBlocking {
      assertEquals(MTWApplication::class.java, context.applicationContext.javaClass)
      val journal = File(context.noBackupFilesDir, "installation-v1.json")
      journal.writeText("corrupt")
      val exited = CountDownLatch(1)
      val release = blockWorker(exited)
      try {
        val source = splitAttributionDeeplink("https://my.tt/get/android?utm_source=cold_start")
        instrumentation.runOnMainSync {
          source.captureIfAdmitted(context, null, DeeplinkOpenSource.OS_EXTERNAL)
        }
        startWallet()
        checkWalletApi()
        assertEquals("Optional worker still blocked", 1L, exited.count)
        assertEquals("corrupt", journal.readText())
      } finally {
        release.countDown()
      }
    }

  private fun startWallet() {
    val sdk = context.assets.open("js/mytonwallet-sdk.js").use { it.readBytes() }
    println("INSTALLATION_RUNTIME_SDK_SHA256=${hash(sdk)}")
    instrumentation.startActivitySync(
      Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    )
    await("SDK bridge did not start") { WalletCore.isBridgeReady }
  }

  private fun checkWalletApi() =
    runBlocking {
      val words =
        withTimeout(30_000) {
          requireNotNull(WalletCore.bridge).callApiAsync<Array<String>>("getMnemonicWordList", "[]", Array<String>::class.java)
        }
      assertEquals(2048, requireNotNull(words).size)
    }

  private fun hash(bytes: ByteArray) =
    MessageDigest
      .getInstance("SHA-256")
      .digest(bytes)
      .joinToString("") { "%02x".format(it.toInt() and 255) }

  private fun saturateWorker(): Pair<CountDownLatch, CountDownLatch> {
    val release = blockWorker()
    val drained = CountDownLatch(1)
    repeat(31) { assertTrue(WInstallationStorage.enqueue {}) }
    assertTrue(WInstallationStorage.enqueue { drained.countDown() })
    assertFalse(WInstallationStorage.enqueue {})
    return release to drained
  }

  private fun blockWorker(exited: CountDownLatch? = null): CountDownLatch {
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    assertTrue(
      WInstallationStorage.enqueue {
        entered.countDown()
        try {
          release.await(120, TimeUnit.SECONDS)
        } finally {
          exited?.countDown()
        }
      },
    )
    assertTrue(entered.await(5, TimeUnit.SECONDS))
    return release
  }

  private fun await(
    message: String,
    ready: () -> Boolean,
  ) {
    repeat(300) {
      if (ready()) return
      Thread.sleep(100)
    }
    error(message)
  }

  private fun playStatus(journal: File) =
    JSONObject(journal.readText()).getJSONObject("play").getJSONObject("latest").getString("collectionStatus")

  private fun runSdk(body: String): JSONObject {
    val result = CompletableFuture<String>().orTimeout(30, TimeUnit.SECONDS)
    val bridge = requireNotNull(WalletCore.bridge)

    fun poll(): Unit =
      bridge.evaluateJavascript("window.installationProbe") {
        if (it == "null" && !result.isDone) bridge.postDelayed({ poll() }, 100) else result.complete(it)
      }
    instrumentation.runOnMainSync {
      bridge.evaluateJavascript(
        """
                window.installationProbe = null;
                (async () => {
                  const callbacks = window.airBridge.nativeCallCallbacks;
                  let requestNumber = -1;
                  const nativeCall = (method, first = null, second = null) => {
                    const id = requestNumber--, previous = callbacks[id];
                    return new Promise(resolve => {
                      callbacks[id] = resolve;
                      window.androidApp.nativeCall(id, method, first, second);
                    }).finally(() => previous === undefined ? delete callbacks[id] : callbacks[id] = previous);
                  };
                  try {
                    window.installationProbe = await (async () => { $body })();
                  } catch (error) {
                    window.installationProbe = { error: String(error?.stack ?? error) };
                  }
                })();
            """,
        null,
      )
    }
    bridge.post { poll() }
    return JSONObject(result.get()).also { assertFalse(it.toString(), it.has("error")) }
  }
}
