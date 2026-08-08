package org.mytonwallet.uihome.home.status

import android.os.Handler
import android.os.Looper
import java.lang.ref.WeakReference
import java.util.concurrent.CopyOnWriteArrayList
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.uihome.home.views.UpdateStatusView

object HomeStatusController : WalletCore.EventObserver {

    fun interface Listener {
        fun onStatus(state: UpdateStatusView.State, animated: Boolean)
    }

    private val handler = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArrayList<WeakReference<Listener>>()

    private var registered = false
    private var waitingForNetwork = false
    private var checkUpdatingTimer: Runnable? = null

    var state: UpdateStatusView.State = UpdateStatusView.State.Updated("")
        private set

    fun addListener(listener: Listener) {
        ensureRegistered()
        listeners.forEach { reference ->
            val existing = reference.get()
            if (existing == null || existing == listener) {
                listeners.remove(reference)
            }
        }
        listeners.add(WeakReference(listener))
        listener.onStatus(state, animated = false)
    }

    fun removeListener(listener: Listener) {
        listeners.forEach { reference ->
            if (reference.get() == listener) {
                listeners.remove(reference)
            }
        }
    }

    @Synchronized
    private fun ensureRegistered() {
        if (registered) return
        registered = true
        WalletCore.registerObserver(this)
        waitingForNetwork = !WalletCore.isConnected()
        scheduleUpdate(animated = false)
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.UpdatingStatusChanged -> scheduleUpdate(animated = true)

            is WalletEvent.AccountWillChange,
            is WalletEvent.AccountChanged,
            is WalletEvent.AccountNameChanged -> refreshName()

            WalletEvent.NetworkDisconnected -> {
                waitingForNetwork = true
                emit(animated = true)
            }

            WalletEvent.NetworkConnected -> {
                waitingForNetwork = false
                scheduleUpdate(animated = true)
            }

            else -> {}
        }
    }

    private fun scheduleUpdate(animated: Boolean) {
        checkUpdatingTimer?.let { handler.removeCallbacks(it) }
        if (AccountStore.updatingActivities || AccountStore.updatingBalance) {
            val runnable = Runnable {
                checkUpdatingTimer = null
                emit(animated)
            }
            checkUpdatingTimer = runnable
            handler.postDelayed(runnable, 2000)
        } else {
            checkUpdatingTimer = null
            emit(animated)
        }
    }

    private fun emit(animated: Boolean) {
        val newState = when {
            waitingForNetwork -> UpdateStatusView.State.WaitingForNetwork

            AccountStore.updatingActivities || AccountStore.updatingBalance ->
                UpdateStatusView.State.Updating

            else -> UpdateStatusView.State.Updated(currentName())
        }
        state = newState
        listeners.forEach { it.get()?.onStatus(newState, animated) }
    }

    private fun refreshName() {
        val current = state
        if (current !is UpdateStatusView.State.Updated) return
        val name = currentName()
        if (name == current.customText) return
        val newState = UpdateStatusView.State.Updated(name)
        state = newState
        listeners.forEach { it.get()?.onStatus(newState, animated = true) }
    }

    private fun currentName(): String {
        val nextAccountId = WalletCore.nextAccountId
        val account = if (nextAccountId != null) {
            AccountStore.accountById(nextAccountId) ?: AccountStore.activeAccount
        } else {
            AccountStore.activeAccount
        }
        return account?.name ?: ""
    }
}
