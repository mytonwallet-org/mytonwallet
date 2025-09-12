package org.mytonwallet.app_air.ledger.connectionManagers

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.ledger.live.ble.BleManager
import com.ledger.live.ble.BleManagerFactory
import com.ledger.live.ble.model.BleDeviceModel
import org.mytonwallet.app_air.ledger.LedgerDevice
import org.mytonwallet.app_air.ledger.LedgerManager.ConnectionState
import org.mytonwallet.app_air.ledger.helpers.APDUHelpers
import org.mytonwallet.app_air.ledger.helpers.VersionComparisonHelpers
import org.mytonwallet.app_air.walletcore.models.LedgerAppInfo
import java.lang.ref.WeakReference

object LedgerBleManager : ILedgerConnectionManager {
    private var context: WeakReference<Context>? = null
    private val bleManager: BleManager?
        get() {
            return context?.get()?.let {
                BleManagerFactory.newInstance(it)
            }
        }

    fun init(context: Context) {
        this.context = WeakReference(context)
    }

    private var isStopped = true

    private var devices = emptyList<BleDeviceModel>()
    private var triedDevices = mutableListOf<BleDeviceModel>()
    private var selectedDevice: BleDeviceModel? = null
    private var currentAppInfo: LedgerAppInfo? = null

    fun isPermissionGranted(): Boolean {
        return bleManager?.isPermissionGranted() == true
    }

    override fun startConnection(onUpdate: (ConnectionState) -> Unit) {
        if (!isStopped)
            stopConnection()
        isStopped = false
        onUpdate(ConnectionState.Connecting)
        bleManager?.startScanning { devices ->
            this.devices = devices
            if (selectedDevice == null)
                selectDevice(devices.first(), onUpdate)
        }
    }

    override fun stopConnection() {
        bleManager?.stopScanning()
        if (bleManager?.isConnected == true)
            bleManager?.disconnect()
        devices = emptyList()
        triedDevices = mutableListOf()
        selectedDevice = null
        isStopped = true
    }

    private fun selectDevice(device: BleDeviceModel, onUpdate: (ConnectionState) -> Unit) {
        selectedDevice = device
        bleManager?.connect(device.id, onConnectSuccess = {
            if (selectedDevice?.id != device.id)
                return@connect
            onUpdate(ConnectionState.ConnectingToTonApp(LedgerDevice.Ble(it)))
            connectToTonApp(device, onUpdate)
        }, onConnectError = {
            if (selectedDevice?.id != device.id)
                return@connect
            triedDevices.add(selectedDevice!!)
            selectedDevice = null
            val nextDevice = devices.find { nextDeviceCandidate ->
                triedDevices.find { triedDevice ->
                    triedDevice.id == nextDeviceCandidate.id
                } == null
            }
            nextDevice?.let {
                selectDevice(it, onUpdate)
            } ?: run {
                selectedDevice = null
                onUpdate(
                    ConnectionState.Error(
                        step = ConnectionState.Error.Step.CONNECT,
                        shortMessage = null
                    )
                )
            }
        })
    }

    private fun connectToTonApp(
        device: BleDeviceModel,
        onUpdate: (ConnectionState) -> Unit,
        retriesLeft: Int = 3
    ) {
        try {
            bleManager?.send(APDUHelpers.currentApp(), {
                val openAppData = APDUHelpers.decodeReadable(it)
                if (openAppData.first() == "TON") {
                    currentAppInfo = LedgerAppInfo(
                        isUnsafeSupported = VersionComparisonHelpers.compareVersions(
                            openAppData[1],
                            "2.1.0"
                        ) >= 0,
                        isJettonIdSupported = VersionComparisonHelpers.compareVersions(
                            openAppData[1],
                            "2.2.0"
                        ) >= 0
                    )
                    onUpdate(ConnectionState.Done(LedgerDevice.Ble(device), openAppData[1]))
                } else {
                    onUpdate(
                        ConnectionState.Error(
                            step = ConnectionState.Error.Step.TON_APP,
                            shortMessage = null
                        )
                    )
                }
            }, {
                onUpdate(
                    ConnectionState.Error(
                        step = ConnectionState.Error.Step.TON_APP,
                        shortMessage = null
                    )
                )
            })
        } catch (e: Throwable) {
            if (retriesLeft > 0) {
                Handler(Looper.getMainLooper()).postDelayed({
                    connectToTonApp(device, onUpdate, retriesLeft - 1)
                }, 500)
            } else {
                onUpdate(
                    ConnectionState.Error(
                        step = ConnectionState.Error.Step.TON_APP,
                        shortMessage = null
                    )
                )
            }
        }
    }

    override fun getPublicKey(walletIndex: Int, onCompletion: (publicKey: List<Int>?) -> Unit) {
        bleManager?.send(APDUHelpers.getPublicKey(false, 0, walletIndex), {
            onCompletion(APDUHelpers.decode(it.substring(0, it.length - 4)))
        }, {
            onCompletion(null)
        })
    }

    override fun write(
        apdu: String,
        onSuccess: (String) -> Unit,
        onError: (String) -> Unit,
    ) {
        bleManager?.send(apdu, onSuccess, onError)
    }
}
