package org.mytonwallet.app_air.walletcore.stores

import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import java.util.concurrent.Executors

object AddressStore : IStore {
    private var executor = Executors.newSingleThreadExecutor()

    data class AddressData(
        val accountId: String,
        var savedAddresses: MutableList<MSavedAddress>? = null,
        var otherAccountAddresses: MutableList<MSavedAddress>? = null,
    )

    @Volatile
    var addressData: AddressData? = null
        private set

    fun loadFromCache(accountId: String) {
        addressData = AddressData(
            accountId = accountId,
            savedAddresses = mutableListOf(),
            otherAccountAddresses = mutableListOf(),
        )
        executor.execute {
            val savedAddresses = buildSavedAddresses(accountId)
            val otherAccountAddresses = buildOtherAccountAddresses(accountId)

            Handler(Looper.getMainLooper()).post {
                if (AccountStore.activeAccountId != accountId)
                    return@post
                addressData = AddressData(accountId, savedAddresses, otherAccountAddresses)
                WalletCore.notifyEvent(WalletEvent.AccountSavedAddressesChanged)
            }
        }
    }

    private fun buildSavedAddresses(accountId: String): MutableList<MSavedAddress> {
        val addressesJSONArray = WGlobalStorage.getAccountAddresses(accountId)
        val addressesArray = ArrayList<MSavedAddress>()
        for (i in 0 until (addressesJSONArray?.length() ?: 0)) {
            val savedAddressJson = addressesJSONArray?.optJSONObject(i) ?: continue
            MSavedAddress.fromJson(savedAddressJson)?.let { savedAddress ->
                addressesArray.add(savedAddress)
            }
        }
        return addressesArray
    }

    private fun buildOtherAccountAddresses(excludingAccountId: String): MutableList<MSavedAddress> {
        val otherAccountAddresses = mutableListOf<MSavedAddress>()
        WalletCore.getAllAccounts().forEach { account ->
            if (account.accountId == excludingAccountId) {
                return@forEach
            }
            account.byChain.forEach { (chain, chainData) ->
                otherAccountAddresses.add(
                    MSavedAddress(
                        address = chainData.address,
                        name = account.name,
                        chain = chain,
                        domain = chainData.domain?.trim()?.takeIf { it.isNotEmpty() },
                        accountId = account.accountId,
                    )
                )
            }
        }
        return otherAccountAddresses
    }

    fun updatedAccountName(accountId: String, accountName: String) {
        addressData?.let { data ->
            data.otherAccountAddresses?.forEach { address ->
                if (address.accountId == accountId) {
                    address.name = accountName
                }
            }
        }
    }

    fun updatedAccountByChain(accountId: String, byChain: Map<String, MAccount.AccountChain>) {
        val data = addressData ?: return
        val accountName = AccountStore.accountById(accountId)?.name ?: ""
        val others = (data.otherAccountAddresses ?: mutableListOf())
            .filter { it.accountId != accountId }
            .toMutableList()

        if (data.accountId != accountId) {
            byChain.forEach { (chain, chainData) ->
                others.add(
                    MSavedAddress(
                        address = chainData.address,
                        name = accountName,
                        chain = chain,
                        domain = chainData.domain?.trim()?.takeIf { it.isNotEmpty() },
                        accountId = accountId,
                    )
                )
            }
        }
        data.otherAccountAddresses = others
    }

    override fun wipeData() {
        clearCache()
    }

    override fun clearCache() {
        executor.shutdownNow()
        executor = Executors.newSingleThreadExecutor()
        addressData = null
    }

    fun getSavedAddress(address: String, chain: String? = null): MSavedAddress? {
        return addressData?.savedAddresses?.firstOrNull {
            it.address == address && (chain == null || it.chain == chain)
        }
    }

    fun getAddress(address: String, chain: String? = null): MSavedAddress? {
        return addressData?.otherAccountAddresses?.firstOrNull {
            it.address == address && (chain == null || it.chain == chain)
        } ?: getSavedAddress(address, chain)
    }

    fun getDomain(address: String, chain: String? = null): String? {
        return getAddress(address, chain)?.domain?.trim()?.takeIf { it.isNotEmpty() }
    }

    fun addAddress(address: MSavedAddress) {
        val addressData = this.addressData ?: return
        addressData.savedAddresses = (addressData.savedAddresses ?: mutableListOf()).apply {
            add(address)
        }
        WGlobalStorage.setAccountAddresses(
            addressData.accountId,
            JSONArray().apply {
                addressData.savedAddresses?.forEach {
                    put(it.toDictionary())
                }
            }
        )
    }

    fun removeAddress(address: String) {
        val addressData = this.addressData ?: return
        val savedAddresses = addressData.savedAddresses ?: return
        addressData.savedAddresses = savedAddresses.filter {
            it.address != address
        }.toMutableList()
        WGlobalStorage.setAccountAddresses(
            addressData.accountId,
            JSONArray().apply {
                addressData.savedAddresses?.forEach {
                    put(it.toDictionary())
                }
            }
        )
    }
}
