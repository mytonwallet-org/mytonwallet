package org.mytonwallet.app_air.walletcore.stores

import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
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
        )
        executor.execute {
            val addressesJSONArray = WGlobalStorage.getAccountAddresses(accountId)
            val addressesArray = ArrayList<MSavedAddress>()
            for (i in 0 until (addressesJSONArray?.length() ?: 0)) {
                val savedAddressJson = addressesJSONArray?.get(i) as JSONObject
                MSavedAddress.fromJson(savedAddressJson)?.let { savedAddress ->
                    addressesArray.add(savedAddress)
                }
            }
            val accounts = WalletCore.getAllAccounts()
            val otherAccountAddresses = mutableListOf<MSavedAddress>()
            for (account in accounts) {
                for (chain in account.addressByChain.keys) {
                    otherAccountAddresses.add(
                        MSavedAddress(
                            account.addressByChain[chain] ?: "",
                            account.name,
                            chain,
                            accountId = account.accountId
                        )
                    )
                }
            }

            Handler(Looper.getMainLooper()).post {
                if (AccountStore.activeAccountId != accountId)
                    return@post
                addressData = AddressData(accountId, addressesArray, otherAccountAddresses)
            }
        }
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

    override fun wipeData() {
        clearCache()
    }

    override fun clearCache() {
        executor.shutdownNow()
        executor = Executors.newSingleThreadExecutor()
        addressData = null
    }

    fun getSavedAddress(address: String): MSavedAddress? {
        return addressData?.savedAddresses?.firstOrNull {
            it.address == address
        }
    }

    fun getAddress(address: String): MSavedAddress? {
        return addressData?.otherAccountAddresses?.firstOrNull {
            it.address == address
        } ?: getSavedAddress(address)
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
