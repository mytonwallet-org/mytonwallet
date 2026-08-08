package org.mytonwallet.app_air.ledger.usb

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import androidx.core.content.ContextCompat
import java.io.ByteArrayOutputStream
import org.mytonwallet.app_air.walletbasecontext.logger.Logger

class USBManager(val applicationContext: Context) {
    var hidDevice: HIDDevice? = null
    private var usbManager: UsbManager? = null
    private var usbReceiver: BroadcastReceiver? = null
    private var usbReceiverRegistered = false
    private var selectedDevice: UsbDevice? = null

    init {
        usbManager = applicationContext.getSystemService(Context.USB_SERVICE) as UsbManager
        usbReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent) {
                val action = intent.action
                if (UsbManager.ACTION_USB_DEVICE_ATTACHED == action) {
                    val device = intent.getParcelableExtra<UsbDevice?>(UsbManager.EXTRA_DEVICE)
                    if (device != null) {
                        onDeviceStateChanged("onDeviceConnect", device)
                    }
                } else if (UsbManager.ACTION_USB_DEVICE_DETACHED == action) {
                    val device = intent.getParcelableExtra<UsbDevice?>(UsbManager.EXTRA_DEVICE)
                    if (device != null) {
                        onDeviceStateChanged("onDeviceDisconnect", device)
                    }
                }
            }
        }
    }

    fun start() {
        if (!usbReceiverRegistered) {
            val filter = IntentFilter()
            filter.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            ContextCompat.registerReceiver(
                applicationContext,
                usbReceiver,
                filter,
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
            usbReceiverRegistered = true
        }
    }

    fun stop() {
        if (usbReceiverRegistered && usbReceiver != null) {
            applicationContext.unregisterReceiver(usbReceiver)
            usbReceiverRegistered = false
            selectedDevice = null
        }
    }

    private fun onDeviceStateChanged(event: String?, device: UsbDevice) {
        // notifyListeners(event, device)
    }

    fun getDeviceList(): MutableCollection<UsbDevice?> =
        usbManager?.deviceList?.values ?: mutableListOf()

    var onDeviceConnected: ((device: HIDDevice?) -> Unit)? = null
    fun openDevice(deviceId: Int, onDeviceConnected: (deviceId: HIDDevice?) -> Unit) {
        this.onDeviceConnected = onDeviceConnected
        val manager = usbManager ?: throw IllegalStateException("USB manager is unavailable")
        val deviceList = manager.deviceList

        hidDevice?.let {
            it.close()
            hidDevice = null
        }

        for (device in deviceList.values) {
            if (device.deviceId == deviceId) {
                selectedDevice = device
                break
            }
        }

        val device = selectedDevice
        if (device != null) {
            if (manager.hasPermission(device)) {
                openSelectedDevice(device)
            } else {
                requestUsbPermission(manager, device)
            }
        } else {
            throw IllegalStateException("USB device not found")
        }
    }

    private fun requestUsbPermission(manager: UsbManager, device: UsbDevice?) {
        try {
            val permIntent = PendingIntent.getBroadcast(
                applicationContext,
                0,
                Intent(ACTION_USB_PERMISSION),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            registerBroadcastReceiver()
            manager.requestPermission(device, permIntent)
        } catch (e: Exception) {
            throw IllegalStateException("USB permission request failed", e)
        }
    }

    private fun registerBroadcastReceiver() {
        val intFilter = IntentFilter(ACTION_USB_PERMISSION)
        val receiver: BroadcastReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent) {
                if (ACTION_USB_PERMISSION == intent.action) {
                    synchronized(this) {
                        unregisterReceiver(this)
                        val manager = usbManager
                        val device = selectedDevice
                        if (manager == null || device == null || !manager.hasPermission(device)) {
                            onDeviceConnected?.invoke(null)
                            return
                        }
                        openSelectedDevice(device)
                    }
                }
            }
        }
        ContextCompat.registerReceiver(
            applicationContext,
            receiver,
            intFilter,
            ContextCompat.RECEIVER_EXPORTED
        )
    }

    private fun unregisterReceiver(receiver: BroadcastReceiver?) {
        try {
            applicationContext.unregisterReceiver(receiver)
        } catch (e: Exception) {
            Logger.e(
                Logger.LogTag.LEDGER,
                "USB receiver unregister failed error=${e.javaClass.simpleName}"
            )
        }
    }

    private fun openSelectedDevice(device: UsbDevice) {
        val openedDevice = try {
            val manager = usbManager ?: throw IllegalStateException("USB manager is unavailable")
            HIDDevice(manager, device)
        } catch (e: Exception) {
            Logger.e(
                Logger.LogTag.LEDGER,
                "USB device open failed deviceId=${device.deviceId} " +
                    "error=${e.javaClass.simpleName}"
            )
            onDeviceConnected?.invoke(null)
            return
        }
        hidDevice = openedDevice
        onDeviceConnected?.invoke(openedDevice)
    }

    fun closeDevice(deviceId: Int) {
        val device = hidDevice ?: return
        if (device.deviceId != deviceId) return

        device.close()
        hidDevice = null
        selectedDevice = null
    }

    fun exchange(deviceId: Int, apduHex: String, onCompletion: (String?) -> Unit) {
        val device = hidDevice
            ?.takeIf { it.deviceId == deviceId }
            ?: throw IllegalStateException("USB device is not connected")

        val apduCommand: ByteArray? = hexToBin(apduHex)
        try {
            device.exchange(apduCommand, onCompletion = onCompletion)
        } catch (e: Exception) {
            throw IllegalStateException("USB exchange failed", e)
        }
    }

    companion object {
        private const val ACTION_USB_PERMISSION =
            "org.mytonwallet.app.USB_PERMISSION"

        fun hexToBin(src: String): ByteArray? {
            val result = ByteArrayOutputStream()
            var i = 0
            while (i < src.length) {
                val x = src.get(i)
                if (!((x >= '0' && x <= '9') || (x >= 'A' && x <= 'F') || (x >= 'a' && x <= 'f'))) {
                    i++
                    continue
                }
                try {
                    result.write(("" + src.get(i) + src.get(i + 1)).toInt(16))
                    i += 2
                } catch (e: Exception) {
                    return null
                }
            }
            return result.toByteArray()
        }
    }
}
