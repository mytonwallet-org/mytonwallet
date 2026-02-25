package org.mytonwallet.app_air.ledger.connectionManagers

import android.content.Context
import android.hardware.usb.UsbDevice
import org.mytonwallet.app_air.ledger.LedgerDevice
import org.mytonwallet.app_air.ledger.LedgerManager.ConnectionState
import org.mytonwallet.app_air.ledger.usb.HIDDevice
import org.mytonwallet.app_air.ledger.usb.USBManager
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

object LedgerUsbManager : ILedgerConnectionManager {
    private const val LEDGER_VENDOR_ID = 0x2c97

    private lateinit var applicationContext: Context
    private val usbManager: USBManager by lazy {
        USBManager(applicationContext)
    }

    fun init(applicationContext: Context) {
        this.applicationContext = applicationContext
    }

    private var isStopped = true

    private var devices = emptyList<UsbDevice>()
    private var triedDevices = mutableListOf<UsbDevice>()
    private var selectedDevice: UsbDevice? = null

    override fun startConnection(onUpdate: (ConnectionState) -> Unit) {
        if (!isStopped)
            stopConnection()
        usbManager.start()
        isStopped = false
        onUpdate(ConnectionState.Connecting)
        this.devices =
            usbManager.getDeviceList().toList().filterNotNull()
                .filter { it.vendorId == LEDGER_VENDOR_ID }
        if (selectedDevice == null && this.devices.isNotEmpty())
            selectDevice(devices.first(), onUpdate)
        else
            onUpdate(
                ConnectionState.Error(
                    step = ConnectionState.Error.Step.CONNECT,
                    shortMessage = null
                )
            )
    }

    override fun stopConnection() {
        if (usbManager.hidDevice != null)
            usbManager.hidDevice?.close()
        usbManager.stop()
        devices = emptyList()
        triedDevices = mutableListOf()
        selectedDevice = null
        isStopped = true
    }

    private fun selectDevice(device: UsbDevice, onUpdate: (ConnectionState) -> Unit) {
        selectedDevice = device
        try {
            usbManager.openDevice(device.deviceId, onDeviceConnected = {
                if (it == null) {
                    onUpdate(
                        ConnectionState.Error(
                            step = ConnectionState.Error.Step.CONNECT,
                            shortMessage = null
                        )
                    )
                    return@openDevice
                }
                if (selectedDevice?.deviceId != device.deviceId || it.deviceId != device.deviceId)
                    return@openDevice
                onUpdate(ConnectionState.ConnectingToTonApp(LedgerDevice.Usb(it)))
                connectToTonApp(it, onUpdate)
            })
        } catch (_: Throwable) {
            triedDevices.add(selectedDevice!!)
            selectedDevice = null
            val nextDevice = devices.find { nextDeviceCandidate ->
                triedDevices.find { triedDevice ->
                    triedDevice.deviceId == nextDeviceCandidate.deviceId
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
        }
    }

    private fun connectToTonApp(
        device: HIDDevice,
        onUpdate: (ConnectionState) -> Unit,
    ) {
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
                onUpdate(ConnectionState.Done(LedgerDevice.Usb(device)))
            }
        )
    }

    override fun write(
        apdu: String,
        onSuccess: (String) -> Unit,
        onError: (String) -> Unit,
    ) {
        try {
            usbManager.exchange(selectedDevice!!.deviceId, apdu) {
                it?.let {
                    onSuccess(it)
                } ?: run {
                    onError("")
                }
            }
        } catch (e: Throwable) {
            onError(e.message ?: "")
        }
    }
}
