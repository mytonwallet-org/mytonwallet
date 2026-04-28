import Foundation
import WalletCore
import WalletContext

private struct EvmChainIdEntry: Encodable {
    let chain: String
    let network: String
}

struct EvmConnectInjectionScript {
    static var source: String {
        let chainIdsJSON = makeChainIdsJSON()
        let activeNetwork = AccountStore.activeNetwork.rawValue
        let defaultCaip2 = makeDefaultCaip2()
        let appName = makeJSONString(APP_NAME)
        let rdns = makeJSONString(IS_GRAM_WALLET ? "io.gramwallet" : "app.mytonwallet")
        let defaultCaip2JSON = makeJSONString(defaultCaip2)
        let installFlag = IS_GRAM_WALLET ? "__gramWalletEvmConnectorInstalled" : "__mtwEvmConnectorInstalled"
        return #"""
        (function() {
            if (window.\#(installFlag)) return;
            window.\#(installFlag) = true;
            if (!window._mtwAir_invokeFunc) return;

            const APP_NAME = \#(appName);
            const RDNS = \#(rdns);
            const EVM_CHAIN_IDS = \#(chainIdsJSON);
            const ACTIVE_NETWORK = '\#(activeNetwork)';
            const DEFAULT_CAIP2 = \#(defaultCaip2JSON);
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

            function currentNetworkCaips() {
                const current = Object.keys(EVM_CHAIN_IDS).filter((caip2) => EVM_CHAIN_IDS[caip2].network === ACTIVE_NETWORK);
                return current.length ? current : Object.keys(EVM_CHAIN_IDS);
            }

            function requestedChains() {
                const seen = new Set();
                return currentNetworkCaips().map((caip2) => EVM_CHAIN_IDS[caip2]).filter((item) => {
                    const key = `${item.chain}:${item.network}`;
                    if (seen.has(key)) return false;
                    seen.add(key);
                    return true;
                });
            }

            function caip2ToHexChainId(caip2) {
                const match = /^eip155:(\d+)$/.exec(caip2);
                if (!match) throw makeProviderError(4902, 'Unrecognized chain');
                return `0x${BigInt(match[1]).toString(16)}`;
            }

            function hexToEip155Caip2(hex) {
                const withPrefix = String(hex || '').startsWith('0x') ? String(hex) : `0x${hex}`;
                return `eip155:${BigInt(withPrefix)}`;
            }

            function normalizeHexChainId(hex) {
                const withPrefix = String(hex || '').startsWith('0x') ? String(hex) : `0x${hex}`;
                return `0x${BigInt(withPrefix).toString(16)}`;
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
                const icon = document.querySelector('link[rel*="icon"]')?.href || `${window.location.origin}/favicon.ico` || '';
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
                    this.provider = {
                        isMyTonWallet: \#(!IS_GRAM_WALLET),
                        isGramWallet: \#(IS_GRAM_WALLET),
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
                    }[name];
                    if (!method) return Promise.reject(makeProviderError(-32601, `Unknown wallet op: ${name}`));
                    return new Promise((resolve, reject) => window._mtwAir_invokeFunc(method, args, resolve, reject));
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

                    this.sessionChains = response.session.chains || [];
                    const evm = this.evmChains;
                    if (!evm.length) return false;

                    const caip0 = getCaip2ForSessionChain(evm[0].chain, evm[0].network);
                    this.selectedCaip2 = this.selectedCaip2 !== caip0
                        ? this.selectedCaip2
                        : caip0 || this.selectedCaip2;

                    this.emit('connect', [{ chainId: this.chainIdHex() }]);
                    this.emit('accountsChanged', [this.accountsLower()]);
                    return true;
                }

                async connectWallet(silent) {
                    const id = ++this.lastGeneratedId;
                    if (silent) {
                        return this.requestWc('reconnect', [id]);
                    }

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
                                const response = await this.connectWallet(false);
                                if (!this.applySessionResult(response)) return [];
                                return this.accountsLower();
                            }
                            case 'eth_accounts': {
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
                                const match = this.evmChains.find((item) =>
                                    getCaip2ForSessionChain(item.chain, item.network) === targetCaip
                                );
                                if (this.evmChains.length && !match) {
                                    return Promise.reject(makeProviderError(4902, 'Chain not added'));
                                }
                                this.selectedCaip2 = targetCaip;
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
                                return Promise.reject(makeProviderError(-32601, `Unsupported method: ${method}`));
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
                        txParams = {
                            ...txParams,
                            chainId: this.selectedCaip2 ? caip2ToHexChainId(this.selectedCaip2) : undefined,
                        };
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

                async disconnect() {
                    try {
                        await this.requestWc('disconnect', [{ requestId: String(++this.lastGeneratedId) }]);
                    } finally {
                        this.sessionChains = [];
                        this.emit('accountsChanged', [[]]);
                        this.emit('disconnect', [{ code: 4900, message: 'Disconnected' }]);
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
            const svg = \#(injectedWalletIconSvg);
            registerEvmInjectedWallet({
                info: {
                    uuid: (typeof crypto !== 'undefined' && crypto.randomUUID)
                        ? crypto.randomUUID()
                        : `evm-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`,
                    name: APP_NAME,
                    icon: `data:image/svg+xml,${encodeURIComponent(svg)}`,
                    rdns: RDNS,
                },
                provider: evm.provider,
            });
        })();
        """#
    }

    private static func makeChainIdsJSON() -> String {
        var result: [String: EvmChainIdEntry] = [:]
        for chain in ApiChain.allCases where chain.chainStandard == .ethereum {
            for (network, chainId) in chain.walletConnectChainIds {
                result["eip155:\(chainId)"] = EvmChainIdEntry(chain: chain.rawValue, network: network.rawValue)
            }
        }
        let data = try! JSONEncoder().encode(result)
        return String(data: data, encoding: .utf8)!
    }

    private static func makeDefaultCaip2() -> String {
        let network = AccountStore.activeNetwork
        let defaultChain: ApiChain?
        if ApiChain.ethereum.walletConnectChainIds[network] != nil {
            defaultChain = .ethereum
        } else {
            defaultChain = ApiChain.allCases.first {
                $0.chainStandard == .ethereum && $0.walletConnectChainIds[network] != nil
            }
        }
        guard let chain = defaultChain, let chainId = chain.walletConnectChainIds[network] else {
            return "eip155:1"
        }
        return "eip155:\(chainId)"
    }

    private static func makeJSONString(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
    }
}
