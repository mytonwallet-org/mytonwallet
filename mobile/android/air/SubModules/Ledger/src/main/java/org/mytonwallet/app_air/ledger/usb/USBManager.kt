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

    fun getDeviceList(): MutableCollection<UsbDevice?> {
        return usbManager!!.getDeviceList().values
    }

    var onDeviceConnected: ((device: HIDDevice?) -> Unit)? = null
    fun openDevice(deviceId: Int, onDeviceConnected: (deviceId: HIDDevice?) -> Unit) {
        this.onDeviceConnected = onDeviceConnected
        val deviceList = usbManager!!.getDeviceList()

        if (hidDevice != null) {
            hidDevice!!.close()
            hidDevice = null
        }

        for (device in deviceList.values) {
            if (device.deviceId == deviceId) {
                selectedDevice = device
                break
            }
        }

        if (selectedDevice != null) {
            if (usbManager!!.hasPermission(selectedDevice)) {
                openSelectedDevice(selectedDevice!!)
            } else {
                requestUsbPermission(usbManager!!, selectedDevice)
            }
        } else {
            throw Error("DeviceNotFound")
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
            throw Error(e.message)
        }
    }

    private fun registerBroadcastReceiver() {
        val intFilter = IntentFilter(ACTION_USB_PERMISSION)
        val receiver: BroadcastReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent) {
                if (ACTION_USB_PERMISSION == intent.action) {
                    synchronized(this) {
                        unregisterReceiver(this)
                        if (selectedDevice == null || !usbManager!!.hasPermission(selectedDevice)) {
                            onDeviceConnected?.invoke(null)
                            return
                        }
                        openSelectedDevice(selectedDevice!!)
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
            e.printStackTrace()
        }
    }

    private fun openSelectedDevice(device: UsbDevice): Boolean {
        try {
            hidDevice = HIDDevice(usbManager!!, device)
            onDeviceConnected?.invoke(hidDevice!!)
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    fun closeDevice(deviceId: Int) {
        if (hidDevice == null || hidDevice!!.deviceId != deviceId) return

        hidDevice!!.close()
        hidDevice = null
        selectedDevice = null
    }

    fun exchange(deviceId: Int, apduHex: String, onCompletion: (String?) -> Unit) {
        if (hidDevice == null || hidDevice!!.deviceId != deviceId) {
            throw Error("NotConnected")
        }

        val apduCommand: ByteArray? = hexToBin(apduHex)
        try {
            hidDevice!!.exchange(apduCommand, onCompletion = onCompletion)
        } catch (e: Exception) {
            e.printStackTrace()
            throw Error(e.message)
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
