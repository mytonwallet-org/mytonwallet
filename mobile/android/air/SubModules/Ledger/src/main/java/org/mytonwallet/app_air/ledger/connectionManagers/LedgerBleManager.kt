package org.mytonwallet.app_air.ledger.connectionManagers

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.ledger.live.ble.BleManager
import com.ledger.live.ble.BleManagerFactory
import com.ledger.live.ble.model.BleDeviceModel
import org.mytonwallet.app_air.ledger.LedgerDevice
import org.mytonwallet.app_air.ledger.LedgerManager.ConnectionState
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
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
            waitForLedgerApp(device, onUpdate)
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

    private fun waitForLedgerApp(
        device: BleDeviceModel,
        onUpdate: (ConnectionState) -> Unit,
    ) {
        Handler(Looper.getMainLooper()).post {
            WalletCore.call(
                ApiMethod.Other.WaitForLedgerApp(
                    chain = MBlockchain.ton,
                    ApiMethod.Other.WaitForLedgerApp.Options(timeout = 2000)
                ),
                callback = { res, error ->
                    if (res != true || error != null) {
                        onUpdate(
                            ConnectionState.Error(
                                step = ConnectionState.Error.Step.TON_APP,
                                shortMessage = null
                            )
                        )
                        return@call
                    }
                    onUpdate(ConnectionState.Done(LedgerDevice.Ble(device)))
                }
            )
        }
    }

    override fun write(
        apdu: String,
        onSuccess: (String) -> Unit,
        onError: (String) -> Unit,
    ) {
        bleManager?.send(apdu, onSuccess, onError)
    }
}
