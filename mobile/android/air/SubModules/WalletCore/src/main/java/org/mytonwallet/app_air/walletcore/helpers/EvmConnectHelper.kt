package org.mytonwallet.app_air.walletcore.helpers

import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletbasecontext.R as BaseR

object EvmConnectHelper {

    private val isGramWallet: Boolean
        get() = ApplicationContextHolder.isGramApp

    private val installFlag: String
        get() = if (isGramWallet) "__gramWalletEvmConnectorInstalled" else "__mtwEvmConnectorInstalled"

    private val rdns: String
        get() = if (isGramWallet) "io.gramwallet" else "app.mytonwallet"

    private val appName: String
        get() = ApplicationContextHolder.applicationContext.getString(BaseR.string.app_locale_name_key)

    private val activeNetwork: String
        get() = (AccountStore.activeAccount?.network ?: MBlockchainNetwork.MAINNET).value

    private fun makeChainIdsJson(): String {
        val obj = JSONObject()
        for (chain in MBlockchain.supportedChains) {
            val cfg = chain.config ?: continue
            if (cfg.chainStandard != "ethereum") continue
            for ((network, chainId) in cfg.walletConnectChainIds) {
                val entry = JSONObject().apply {
                    put("chain", chain.name)
                    put("network", network.value)
                }
                obj.put("eip155:$chainId", entry)
            }
        }
        return obj.toString()
    }

    private fun makeDefaultCaip2(): String {
        val network = AccountStore.activeAccount?.network ?: MBlockchainNetwork.MAINNET
        val ethChainId = MBlockchain.ethereum.config?.walletConnectChainIds?.get(network)
        if (ethChainId != null) return "eip155:$ethChainId"
        for (chain in MBlockchain.supportedChains) {
            val cfg = chain.config ?: continue
            if (cfg.chainStandard != "ethereum") continue
            cfg.walletConnectChainIds[network]?.let { return "eip155:$it" }
        }
        return "eip155:1"
    }

    private fun jsonString(value: String): String = JSONObject.quote(value)

    fun inject(): String {
        val chainIdsJson = makeChainIdsJson()
        val defaultCaip2 = makeDefaultCaip2()
        val appNameJson = jsonString(appName)
        val rdnsJson = jsonString(rdns)
        val defaultCaip2Json = jsonString(defaultCaip2)
        val isMyTonWalletLiteral = if (isGramWallet) "false" else "true"
        val isGramWalletLiteral = if (isGramWallet) "true" else "false"
        val svgLiteral = jsonString(InjectedWalletIcon.svg(isGramWallet))

        return """
        (function() {
            if (window.$installFlag) return;
            window.$installFlag = true;
            if (!window._mtwAir_invokeFunc) return;

            const APP_NAME = $appNameJson;
            const RDNS = $rdnsJson;
            const EVM_CHAIN_IDS = $chainIdsJson;
            const ACTIVE_NETWORK = '$activeNetwork';
            const DEFAULT_CAIP2 = $defaultCaip2Json;
            const METHODS = [
                'eth_sendTransaction',
                'eth_signTransaction',
                'personal_sign',
                'eth_sign',
                'eth_signTypedData',
                'eth_signTypedData_v3',
                'eth_signTypedData_v4',
                'wallet_getCapabilities',
            ];

            // Read-only JSON-RPC methods we forward through walletConnect_proxyEvmRpc.
            // Mirrors READONLY_EVM_RPC_METHODS in the SDK adapter; the wallet side enforces
            // the same set, this list keeps us from making round-trips for clearly unsupported
            // methods (and pollutes logs less).
            const READONLY_RPC_METHODS = new Set([
                'eth_blockNumber',
                'eth_getBalance',
                'eth_call',
                'eth_estimateGas',
                'eth_gasPrice',
                'eth_maxPriorityFeePerGas',
                'eth_feeHistory',
                'eth_getTransactionCount',
                'eth_getTransactionByHash',
                'eth_getTransactionReceipt',
                'eth_getCode',
                'eth_getStorageAt',
                'eth_getBlockByNumber',
                'eth_getBlockByHash',
                'eth_getLogs',
                'eth_getBlockTransactionCountByNumber',
                'eth_getBlockTransactionCountByHash',
                'eth_protocolVersion',
                'eth_syncing',
                'net_listening',
                'web3_clientVersion',
            ]);

            // Per-method TTLs (ms) for readonly RPC coalescing. See EvmConnectInjectionScript.swift
            // for the rationale; kept in sync across platforms.
            const READ_CACHE_TTL_MS = {
                eth_blockNumber: 1500,
                eth_gasPrice: 1500,
                eth_maxPriorityFeePerGas: 1500,
                eth_syncing: 30000,
                eth_protocolVersion: 600000,
                net_listening: 600000,
                web3_clientVersion: 600000,
            };

            function currentNetworkCaips() {
                const current = Object.keys(EVM_CHAIN_IDS).filter((caip2) => EVM_CHAIN_IDS[caip2].network === ACTIVE_NETWORK);
                return current.length ? current : Object.keys(EVM_CHAIN_IDS);
            }

            function requestedChains() {
                const seen = new Set();
                return currentNetworkCaips().map((caip2) => EVM_CHAIN_IDS[caip2]).filter((item) => {
                    const key = item.chain + ':' + item.network;
                    if (seen.has(key)) return false;
                    seen.add(key);
                    return true;
                });
            }

            function caip2ToHexChainId(caip2) {
                const match = /^eip155:(\d+)$/.exec(caip2);
                if (!match) throw makeProviderError(4902, 'Unrecognized chain');
                return '0x' + BigInt(match[1]).toString(16);
            }

            function hexToEip155Caip2(hex) {
                const withPrefix = String(hex || '').startsWith('0x') ? String(hex) : ('0x' + hex);
                return 'eip155:' + BigInt(withPrefix);
            }

            function normalizeHexChainId(hex) {
                const withPrefix = String(hex || '').startsWith('0x') ? String(hex) : ('0x' + hex);
                return '0x' + BigInt(withPrefix).toString(16);
            }

            function isSupportedCaip(caip2) {
                return currentNetworkCaips().includes(caip2);
            }

            function firstSupportedCaip() {
                return isSupportedCaip(DEFAULT_CAIP2) ? DEFAULT_CAIP2 : currentNetworkCaips()[0];
            }

            function getCaip2ForSessionChain(chain, network) {
                return Object.entries(EVM_CHAIN_IDS).find(([, value]) => value.chain === chain && value.network === network)?.[0];
            }

            function looksLikeAddress(value) {
                return typeof value === 'string' && /^0x[a-fA-F0-9]{40}$/.test(value);
            }

            function makeProviderError(code, message) {
                const error = new Error(message);
                error.code = code;
                return error;
            }

            function normalizeParams(params) {
                if (params === undefined || params === null) return [];
                return Array.isArray(params) ? params : [params];
            }

            function metadata() {
                const icon = document.querySelector('link[rel*="icon"]')?.href || (window.location.origin + '/favicon.ico') || '';
                return {
                    url: window.origin,
                    name: document.querySelector('meta[property*="og:title"]')?.content || document.title || window.location.hostname,
                    description: '',
                    icons: [icon],
                };
            }

            function registerEvmInjectedWallet(detail) {
                const frozenDetail = Object.freeze({
                    info: Object.freeze({ ...detail.info }),
                    provider: detail.provider,
                });

                function announceProvider() {
                    window.dispatchEvent(new CustomEvent('eip6963:announceProvider', { detail: frozenDetail }));
                }

                announceProvider();
                window.addEventListener('eip6963:requestProvider', announceProvider);

                if (!window.ethereum) {
                    window.ethereum = detail.provider;
                }

                const interval = setInterval(announceProvider, 1000);
                setTimeout(() => clearInterval(interval), 10000);

                return frozenDetail;
            }

            class EvmConnect {
                constructor() {
                    this.lastGeneratedId = 0;
                    this.listeners = new Map();
                    this.sessionChains = [];
                    this.selectedCaip2 = firstSupportedCaip();
                    this._readCache = new Map();
                    // Short-TTL cache for silent reconnect to absorb Reown/wagmi polling
                    // (eth_accounts is polled at 100+/s; in-flight dedup alone leaks 60% to the worker).
                    this._silentReconnect = null;
                    this.provider = {
                        isMyTonWallet: $isMyTonWalletLiteral,
                        isGramWallet: $isGramWalletLiteral,
                        request: (args) => this.request(args || {}),
                        on: (event, handler) => {
                            this.addListener(event, handler);
                            return this.provider;
                        },
                        removeListener: (event, handler) => {
                            this.removeListener(event, handler);
                            return this.provider;
                        },
                        send: (payloadOrMethod, paramsOrCallback) => this.send(payloadOrMethod, paramsOrCallback),
                        sendAsync: (payload, callback) => this.sendAsync(payload, callback),
                    };
                    window._mtwAir_eventListeners.push((event) => {
                        if (event && event.event === 'disconnect') {
                            this.onDisconnect();
                        }
                    });
                }

                get evmChains() {
                    const supportedChainNames = new Set(Object.values(EVM_CHAIN_IDS).map((item) => item.chain));
                    return this.sessionChains.filter((item) => supportedChainNames.has(item.chain));
                }

                addListener(event, handler) {
                    if (typeof handler !== 'function') return;
                    let set = this.listeners.get(event);
                    if (!set) {
                        set = new Set();
                        this.listeners.set(event, set);
                    }
                    set.add(handler);
                }

                removeListener(event, handler) {
                    this.listeners.get(event)?.delete(handler);
                }

                emit(event, args) {
                    this.listeners.get(event)?.forEach((listener) => {
                        try {
                            listener(...args);
                        } catch (err) {
                            console.error('EvmConnect:emit', err);
                        }
                    });
                }

                requestWc(name, args = []) {
                    const method = {
                        connect: 'walletConnect:connect',
                        reconnect: 'walletConnect:reconnect',
                        disconnect: 'walletConnect:disconnect',
                        sendTransaction: 'walletConnect:sendTransaction',
                        signData: 'walletConnect:signData',
                        proxyEvmRpc: 'walletConnect:proxyEvmRpc',
                    }[name];
                    if (!method) return Promise.reject(makeProviderError(-32601, 'Unknown wallet op: ' + name));
                    return new Promise((resolve, reject) => window._mtwAir_invokeFunc(method, args, resolve, reject));
                }

                currentChain() {
                    const entry = EVM_CHAIN_IDS[this.selectedCaip2];
                    return entry ? entry.chain : undefined;
                }

                async proxyReadRpc(method, params) {
                    const ttl = READ_CACHE_TTL_MS[method];
                    if (!ttl) {
                        return this._dispatchProxyRead(method, params);
                    }
                    const now = Date.now();
                    const cached = this._readCache.get(method);
                    if (cached && cached.expiresAt > now) {
                        return cached.promise;
                    }
                    const promise = this._dispatchProxyRead(method, params);
                    const entry = { promise, expiresAt: now + ttl };
                    this._readCache.set(method, entry);
                    promise.catch(() => {
                        if (this._readCache.get(method) === entry) this._readCache.delete(method);
                    });
                    return promise;
                }

                async _dispatchProxyRead(method, params) {
                    const chain = this.currentChain();
                    if (!chain) {
                        return Promise.reject(makeProviderError(4901, 'No selected chain for RPC proxy'));
                    }
                    const response = await this.requestWc('proxyEvmRpc', [{ chain, method, params }]);
                    if (response && response.success) {
                        return response.result;
                    }
                    const err = response && response.error;
                    return Promise.reject(makeProviderError(err && err.code != null ? err.code : -32603, (err && err.message) || 'RPC proxy error'));
                }

                accountsLower() {
                    return [...new Set(this.evmChains.map((item) => item.address.toLowerCase()))];
                }

                chainIdHex() {
                    const selected = isSupportedCaip(this.selectedCaip2) ? this.selectedCaip2 : firstSupportedCaip();
                    return caip2ToHexChainId(selected || 'eip155:1');
                }

                selectedSessionChain() {
                    return this.evmChains.find((item) => getCaip2ForSessionChain(item.chain, item.network) === this.selectedCaip2);
                }

                chainConfigForCaip(caip2) {
                    return EVM_CHAIN_IDS[caip2] || EVM_CHAIN_IDS[firstSupportedCaip()];
                }

                resolveChainForAddress(address, explicitChainId) {
                    const normalized = String(address || '').toLowerCase();
                    const explicitCaip = explicitChainId ? hexToEip155Caip2(normalizeHexChainId(explicitChainId)) : undefined;
                    const preferredCaip = explicitCaip || this.selectedCaip2 || firstSupportedCaip();

                    if (preferredCaip && !isSupportedCaip(preferredCaip)) {
                        throw makeProviderError(4902, 'Unrecognized chain');
                    }

                    const preferred = this.evmChains.find((item) =>
                        item.address.toLowerCase() === normalized
                        && getCaip2ForSessionChain(item.chain, item.network) === preferredCaip
                    );
                    if (preferred) {
                        return { chain: preferred.chain, network: preferred.network };
                    }

                    const addressMatch = this.evmChains.find((item) => item.address.toLowerCase() === normalized);
                    if (addressMatch) {
                        return { chain: addressMatch.chain, network: addressMatch.network };
                    }

                    const fallback = this.chainConfigForCaip(preferredCaip);
                    return { chain: fallback.chain, network: fallback.network };
                }

                applySessionResult(response) {
                    if (!response || !response.success || !response.session) return false;

                    const prevAccounts = this.accountsLower();
                    const prevChainHex = this.chainIdHex();

                    this.sessionChains = response.session.chains || [];
                    const evm = this.evmChains;
                    if (!evm.length) return false;

                    const selectedStillConnected = this.selectedCaip2 && evm.some((item) =>
                        getCaip2ForSessionChain(item.chain, item.network) === this.selectedCaip2
                    );
                    if (!selectedStillConnected) {
                        this.selectedCaip2 = getCaip2ForSessionChain(evm[0].chain, evm[0].network) || firstSupportedCaip();
                    }

                    const nextAccounts = this.accountsLower();
                    const nextChainHex = this.chainIdHex();
                    // Block-bound and gas-price cache must not leak across chains.
                    if (nextChainHex !== prevChainHex) {
                        this._readCache.clear();
                    }
                    // Only emit when state actually changed. Without this, every silent
                    // reconnect (Reown polls eth_accounts ~100/s) re-emits accountsChanged
                    // and pins React-based dapps in a re-render loop until JS heap OOMs.
                    // Fire `connect` on the disconnected->connected transition (prev had no accounts)
                    // even if the resolved chain matches our default fallback (mainnet for most dapps).
                    if (prevAccounts.length === 0 || prevChainHex !== nextChainHex) {
                        this.emit('connect', [{ chainId: nextChainHex }]);
                    }
                    if (prevAccounts.length !== nextAccounts.length
                        || prevAccounts.some((a, i) => a !== nextAccounts[i])) {
                        this.emit('accountsChanged', [nextAccounts]);
                    }
                    return true;
                }

                async connectWallet(silent) {
                    if (silent) {
                        const now = Date.now();
                        const cached = this._silentReconnect;
                        if (cached && cached.expiresAt > now) {
                            return cached.promise;
                        }
                        const id = ++this.lastGeneratedId;
                        const promise = this.requestWc('reconnect', [id]);
                        const entry = { promise, expiresAt: now + 500 };
                        this._silentReconnect = entry;
                        promise.then(
                            (resp) => {
                                if (!resp || !resp.success) {
                                    if (this._silentReconnect === entry) this._silentReconnect = null;
                                }
                            },
                            () => {
                                if (this._silentReconnect === entry) this._silentReconnect = null;
                            },
                        );
                        return promise;
                    }
                    const id = ++this.lastGeneratedId;

                    const payload = {
                        id,
                        params: {
                            id,
                            expiryTimestamp: 0,
                            relays: [],
                            proposer: {
                                publicKey: '',
                                metadata: metadata(),
                            },
                            requiredNamespaces: {},
                            optionalNamespaces: {
                                eip155: {
                                    methods: METHODS,
                                    chains: currentNetworkCaips(),
                                    events: ['accountsChanged', 'chainChanged'],
                                },
                            },
                            pairingTopic: '',
                        },
                    };

                    return this.requestWc('connect', [{
                        protocolType: 'walletConnect',
                        transport: 'inAppBrowser',
                        protocolData: payload,
                        permissions: {
                            isPasswordRequired: false,
                            isAddressRequired: false,
                        },
                        requestedChains: requestedChains(),
                    }]);
                }

                async ensureConnected() {
                    if (this.evmChains.length) return true;
                    try {
                        const response = await this.connectWallet(false);
                        return this.applySessionResult(response);
                    } catch (err) {
                        throw makeProviderError(4001, err instanceof Error ? err.message : 'Rejected');
                    }
                }

                async request(args) {
                    const method = args.method;
                    const params = normalizeParams(args.params);

                    try {
                        switch (method) {
                            case 'eth_requestAccounts': {
                                if (this.evmChains.length) {
                                    return this.accountsLower();
                                }
                                try {
                                    const reconnect = await this.connectWallet(true);
                                    if (this.applySessionResult(reconnect)) {
                                        return this.accountsLower();
                                    }
                                } catch {}
                                const response = await this.connectWallet(false);
                                if (!this.applySessionResult(response)) return [];
                                return this.accountsLower();
                            }
                            case 'eth_accounts': {
                                if (this.evmChains.length) {
                                    return this.accountsLower();
                                }
                                try {
                                    const response = await this.connectWallet(true);
                                    this.applySessionResult(response);
                                } catch {
                                    this.sessionChains = [];
                                }
                                return this.accountsLower();
                            }
                            case 'eth_coinbase': {
                                const accounts = await this.request({ method: 'eth_accounts' });
                                return accounts[0] || null;
                            }
                            case 'eth_chainId':
                                return this.chainIdHex();
                            case 'net_version':
                                return String(BigInt(this.chainIdHex()));
                            case 'wallet_switchEthereumChain':
                            case 'wallet_addEthereumChain': {
                                const chainId = params[0]?.chainId;
                                const targetCaip = hexToEip155Caip2(normalizeHexChainId(chainId));
                                if (!isSupportedCaip(targetCaip)) {
                                    return Promise.reject(makeProviderError(4902, 'Unrecognized chain'));
                                }
                                this.selectedCaip2 = targetCaip;
                                // Block-bound and gas-price cache must not leak across chains.
                                this._readCache.clear();
                                this.emit('chainChanged', [this.chainIdHex()]);
                                return null;
                            }
                            case 'wallet_getCapabilities':
                                return this.getCapabilities(params);
                            case 'wallet_revokePermissions':
                                await this.disconnect();
                                return null;
                            case 'wallet_requestPermissions': {
                                const requested = params[0] || {};
                                if (requested.eth_accounts !== undefined) {
                                    const accounts = await this.request({ method: 'eth_requestAccounts' });
                                    return [{ parentCapability: 'eth_accounts', caveats: [{ type: 'restrictReturnedAccounts', value: accounts }] }];
                                }
                                return [];
                            }
                            case 'eth_sendTransaction':
                            case 'eth_signTransaction':
                                return this.sendTransaction(method, params);
                            case 'personal_sign':
                                return this.signPersonal(params);
                            case 'eth_sign':
                                return this.signEth(params);
                            case 'eth_signTypedData':
                            case 'eth_signTypedData_v3':
                            case 'eth_signTypedData_v4':
                                return this.signTypedData(params);
                            default:
                                if (READONLY_RPC_METHODS.has(method)) {
                                    return this.proxyReadRpc(method, params || []);
                                }
                                return Promise.reject(makeProviderError(-32601, 'Unsupported method: ' + method));
                        }
                    } catch (err) {
                        if (err && typeof err === 'object' && 'code' in err) {
                            return Promise.reject(err);
                        }
                        console.error('EvmConnect:request', err);
                        return Promise.reject(makeProviderError(-32603, err instanceof Error ? err.message : 'Internal error'));
                    }
                }

                async sendTransaction(method, params) {
                    let txParams = params[0];
                    if (txParams && !txParams.chainId) {
                        txParams = { ...txParams, chainId: this.chainIdHex() };
                    }
                    if (!txParams?.from || !looksLikeAddress(txParams.from)) {
                        return Promise.reject(makeProviderError(-32602, 'Invalid params: missing from'));
                    }
                    if (!await this.ensureConnected()) {
                        return Promise.reject(makeProviderError(4001, 'Rejected'));
                    }
                    if (!this.accountsLower().includes(txParams.from.toLowerCase())) {
                        return Promise.reject(makeProviderError(4100, 'Unauthorized'));
                    }

                    const resolved = this.resolveChainForAddress(txParams.from, txParams.chainId);
                    const id = ++this.lastGeneratedId;
                    const response = await this.requestWc('sendTransaction', [{
                        id: String(id),
                        chain: resolved.chain,
                        payload: {
                            isSignOnly: method === 'eth_signTransaction',
                            url: window.origin,
                            address: txParams.from,
                            data: txParams,
                        },
                    }]);

                    if (!response?.success || !response.result) {
                        return Promise.reject(makeProviderError(4001, response?.error?.message || 'Rejected'));
                    }

                    return response.result.result;
                }

                parsePersonalParams(params) {
                    const first = params[0];
                    const second = params[1];
                    if (looksLikeAddress(first)) {
                        return { address: first, data: second };
                    }
                    return { address: second, data: first };
                }

                async signPersonal(params) {
                    const parsed = this.parsePersonalParams(params);
                    return this.signPersonalOrEth(parsed.address, parsed.data, true);
                }

                async signEth(params) {
                    return this.signPersonalOrEth(params[0], params[1], true);
                }

                async signPersonalOrEth(address, data, isEthSign) {
                    if (!looksLikeAddress(address) || typeof data !== 'string') {
                        return Promise.reject(makeProviderError(-32602, 'Invalid params'));
                    }
                    if (!await this.ensureConnected()) {
                        return Promise.reject(makeProviderError(4001, 'Rejected'));
                    }
                    if (!this.accountsLower().includes(address.toLowerCase())) {
                        return Promise.reject(makeProviderError(4100, 'Unauthorized'));
                    }

                    const resolved = this.resolveChainForAddress(address);
                    const id = ++this.lastGeneratedId;
                    const response = await this.requestWc('signData', [{
                        id: String(id),
                        chain: resolved.chain,
                        payload: {
                            url: window.origin,
                            address,
                            data,
                            isEthSign,
                        },
                    }]);

                    if (!response?.success || !response.result) {
                        return Promise.reject(makeProviderError(4001, response?.error?.message || 'Rejected'));
                    }

                    return response.result.result;
                }

                async signTypedData(params) {
                    const first = params[0];
                    const second = params[1];
                    const address = looksLikeAddress(first) ? first : second;
                    const raw = looksLikeAddress(first) ? second : first;
                    if (!looksLikeAddress(address)) {
                        return Promise.reject(makeProviderError(-32602, 'Invalid params: missing address'));
                    }

                    let parsed;
                    try {
                        parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
                    } catch {
                        return Promise.reject(makeProviderError(-32602, 'Invalid typed data'));
                    }

                    const domain = parsed?.domain;
                    const types = parsed?.types;
                    const primaryType = parsed?.primaryType;
                    const message = parsed?.message;
                    if (!domain || !types || !primaryType || !message) {
                        return Promise.reject(makeProviderError(-32602, 'Invalid typed data'));
                    }

                    if (!await this.ensureConnected()) {
                        return Promise.reject(makeProviderError(4001, 'Rejected'));
                    }
                    if (!this.accountsLower().includes(address.toLowerCase())) {
                        return Promise.reject(makeProviderError(4100, 'Unauthorized'));
                    }

                    const resolved = this.resolveChainForAddress(address);
                    const id = ++this.lastGeneratedId;
                    const response = await this.requestWc('signData', [{
                        id: String(id),
                        chain: resolved.chain,
                        payload: {
                            url: window.origin,
                            address,
                            eip712: { domain, types, primaryType, message },
                            isEthSign: true,
                        },
                    }]);

                    if (!response?.success || !response.result) {
                        return Promise.reject(makeProviderError(4001, response?.error?.message || 'Rejected'));
                    }

                    return response.result.result;
                }

                async getCapabilities(params) {
                    const address = params[0];
                    if (this.evmChains.length === 0) {
                        try {
                            const response = await this.connectWallet(true);
                            this.applySessionResult(response);
                        } catch {}
                    }
                    if (address && this.accountsLower().length && !this.accountsLower().includes(String(address).toLowerCase())) {
                        return Promise.reject(makeProviderError(4100, 'Unauthorized'));
                    }

                    const queried = Array.isArray(params[1]) && params[1].length
                        ? params[1].map((item) => normalizeHexChainId(item))
                        : [this.chainIdHex()];
                    const result = {};
                    for (const hex of queried) {
                        const caip2 = hexToEip155Caip2(hex);
                        if (isSupportedCaip(caip2)) {
                            result[hex] = { atomic: { status: 'unsupported' } };
                        }
                    }
                    return result;
                }

                onDisconnect() {
                    ++this.lastGeneratedId;
                    this.sessionChains = [];
                    this.selectedCaip2 = undefined;
                    this._readCache.clear();
                    this._silentReconnect = null;
                    this.emit('accountsChanged', [[]]);
                    this.emit('disconnect', [{ code: 4900, message: 'Disconnected' }]);
                }

                async disconnect() {
                    try {
                        await this.requestWc('disconnect', [{ requestId: String(++this.lastGeneratedId) }]);
                    } finally {
                        this.onDisconnect();
                    }
                }

                send(payloadOrMethod, paramsOrCallback) {
                    if (typeof payloadOrMethod === 'string') {
                        return this.request({ method: payloadOrMethod, params: paramsOrCallback });
                    }
                    return this.request(payloadOrMethod);
                }

                sendAsync(payload, callback) {
                    this.request(payload)
                        .then((result) => callback(null, { id: payload?.id, jsonrpc: payload?.jsonrpc || '2.0', result }))
                        .catch((error) => callback(error, null));
                }
            }

            const evm = new EvmConnect();
            const svg = $svgLiteral;
            registerEvmInjectedWallet({
                info: {
                    uuid: (typeof crypto !== 'undefined' && crypto.randomUUID)
                        ? crypto.randomUUID()
                        : ('evm-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2)),
                    name: APP_NAME,
                    icon: 'data:image/svg+xml,' + encodeURIComponent(svg),
                    rdns: RDNS,
                },
                provider: evm.provider,
            });
        })();
        """
    }
}
