package org.mytonwallet.app_air.walletcore.helpers

object WalletConnectHelper {
    fun inject(): String {
        return """
        (function() {
            if (window.__mtwSolanaConnectorInstalled) return;
            window.__mtwSolanaConnectorInstalled = true;

            const ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
            function decodeBase58(bs58String) {
                const bytes = [0];
                for (let i = 0; i < bs58String.length; i++) {
                    const char = bs58String[i];
                    const value = ALPHABET.indexOf(char);
                    if (value === -1) throw new Error('Invalid Base58 character');
                    for (let j = 0; j < bytes.length; j++) bytes[j] *= 58;
                    bytes[0] += value;
                    let carry = 0;
                    for (let j = 0; j < bytes.length; j++) {
                        bytes[j] += carry;
                        carry = Math.floor(bytes[j] / 256);
                        bytes[j] %= 256;
                    }
                    while (carry) {
                        bytes.push(carry % 256);
                        carry = Math.floor(carry / 256);
                    }
                }
                for (let i = 0; bs58String[i] === '1' && i < bs58String.length - 1; i++) bytes.push(0);
                return new Uint8Array(bytes.reverse());
            }
            function encodeBase58(uint8Array) {
                let result = '';
                let x = BigInt('0');
                for (let i = 0; i < uint8Array.length; i++) {
                    x = x * 256n + BigInt(uint8Array[i]);
                }
                while (x > 0n) {
                    result = ALPHABET[Number(x % 58n)] + result;
                    x = x / 58n;
                }
                for (let i = 0; i < uint8Array.length && uint8Array[i] === 0; i++) {
                    result = '1' + result;
                }
                return result || '1';
            }
            function uint8ArrayToBase64(bytes) {
                let binary = '';
                const len = bytes.byteLength;
                for (let i = 0; i < len; i++) {
                    binary += String.fromCharCode(bytes[i]);
                }
                return btoa(binary);
            }
            function extractResultValue(response) {
                if (!response) {
                    return null;
                }
                if (response.success === false) {
                    return null;
                }
                if (response.result && typeof response.result === 'string') {
                    return response.result;
                }
                if (response.result && typeof response.result.result === 'string') {
                    return response.result.result;
                }
                if (typeof response === 'string') {
                    return response;
                }
                return null;
            }
            function normalizeTransactionBytes(input) {
                if (!input) {
                    return null;
                }
                if (input instanceof Uint8Array) {
                    return input;
                }
                if (input instanceof ArrayBuffer) {
                    return new Uint8Array(input);
                }
                if (typeof input.serialize === 'function') {
                    return new Uint8Array(input.serialize({ requireAllSignatures: false, verifySignatures: false }));
                }
                if (Array.isArray(input)) {
                    return new Uint8Array(input);
                }
                return null;
            }

            class SolanaConnect {
                constructor() {
                    this.lastGeneratedId = 0;
                    this.listeners = new Set();
                    this.accounts = [];
                    this.version = '1.0.0';
                    this.name = 'MyTonWallet';
                    this.icon = '';
                    this.chains = ['solana:mainnet', 'solana:devnet', 'solana:testnet'];
                    this.features = {
                        'standard:connect': {
                            version: '1.0.0',
                            connect: async (input) => {
                                try {
                                    const id = ++this.lastGeneratedId;
                                    if (input && input.silent) {
                                        const response = await this.request('reconnect', [id]);
                                        if (!response.success) {
                                            return { accounts: [] };
                                        }
                                        const standardWalletAddresses = response.session.chains.map((e) => ({
                                            address: e.address,
                                            publicKey: new Uint8Array(decodeBase58(e.address)),
                                            chains: [e.chain + ':' + (e.network === 'mainnet' ? 'mainnet' : 'devnet')],
                                            features: Object.keys(this.features),
                                        }));
                                        this.accounts = standardWalletAddresses;
                                        return { accounts: this.accounts };
                                    }
                                    const metadata = {
                                        url: window.origin,
                                        name: (document.querySelector('meta[property*="og:title"]') || {}).content || document.title,
                                        description: '',
                                        icons: [(document.querySelector('link[rel*="icon"]') || {}).href || (window.location.origin + '/favicon.ico') || ''],
                                    };
                                    const payload = {
                                        id,
                                        params: {
                                            id,
                                            expiryTimestamp: 0,
                                            relays: [],
                                            proposer: {
                                                publicKey: '',
                                                metadata,
                                            },
                                            requiredNamespaces: {},
                                            optionalNamespaces: {
                                                solana: {
                                                    methods: [],
                                                    events: [],
                                                },
                                            },
                                            pairingTopic: '',
                                        },
                                    };
                                    const unifiedPayload = {
                                        protocolType: 'walletConnect',
                                        transport: 'inAppBrowser',
                                        protocolData: payload,
                                        permissions: {
                                            isPasswordRequired: false,
                                            isAddressRequired: false,
                                        },
                                        requestedChains: [{
                                            chain: 'solana',
                                            network: 'mainnet',
                                        }],
                                    };
                                    const response = await this.request('connect', [unifiedPayload]);
                                    if (!response.success) {
                                        return { accounts: [] };
                                    }
                                    const standardWalletAddresses = response.session.chains.map((e) => ({
                                        address: e.address,
                                        publicKey: new Uint8Array(decodeBase58(e.address)),
                                        chains: [e.chain + ':' + (e.network === 'mainnet' ? 'mainnet' : 'devnet')],
                                        features: Object.keys(this.features),
                                    }));
                                    this.accounts = standardWalletAddresses;
                                    return { accounts: this.accounts };
                                } catch (error) {
                                    return { accounts: [] };
                                }
                            },
                        },
                        'standard:disconnect': {
                            version: '1.0.0',
                            disconnect: async () => {
                                await this.request('disconnect', [{ requestId: '1' }]);
                                this.accounts = [];
                            },
                        },
                        'standard:events': {
                            version: '1.0.0',
                            on: (event, listener) => {
                                if (event !== 'change') {
                                    return () => {};
                                }
                                this.listeners.add(listener);
                                return () => {
                                    this.listeners.delete(listener);
                                };
                            },
                        },
                        'solana:signAndSendTransaction': {
                            version: '1.0.0',
                            supportedTransactionVersions: ['legacy', 0],
                            signAndSendTransaction: async (input) => {
                                const id = ++this.lastGeneratedId;
                                const account = input?.account || this.accounts[0];
                                const address = account?.address || '';
                                const txBytes = normalizeTransactionBytes(input?.transaction || input);
                                if (!txBytes || !address) {
                                    console.log('mtw.solana signAndSendTransaction invalid input', { address, hasTx: !!txBytes });
                                    return [];
                                }
                                const unifiedPayload = {
                                    id: String(id),
                                    chain: 'solana',
                                    payload: {
                                        isSignOnly: false,
                                        url: window.origin,
                                        address,
                                        data: uint8ArrayToBase64(txBytes),
                                    },
                                };
                                const response = await this.request('sendTransaction', [unifiedPayload]);
                                console.log('mtw.solana signAndSendTransaction response', response);
                                const resultValue = extractResultValue(response);
                                if (!resultValue) {
                                    return [];
                                }
                                return [{
                                    signature: new Uint8Array(decodeBase58(resultValue)),
                                }];
                            },
                        },
                        'solana:signTransaction': {
                            version: '1.0.0',
                            supportedTransactionVersions: ['legacy', 0],
                            signTransaction: async (input) => {
                                const id = ++this.lastGeneratedId;
                                const account = input?.account || this.accounts[0];
                                const address = account?.address || '';
                                const txBytes = normalizeTransactionBytes(input?.transaction || input);
                                if (!txBytes || !address) {
                                    console.log('mtw.solana signTransaction invalid input', { address, hasTx: !!txBytes });
                                    return [];
                                }
                                const unifiedPayload = {
                                    id: String(id),
                                    chain: 'solana',
                                    payload: {
                                        isSignOnly: true,
                                        url: window.origin,
                                        address,
                                        data: uint8ArrayToBase64(txBytes),
                                    },
                                };
                                const response = await this.request('sendTransaction', [unifiedPayload]);
                                console.log('mtw.solana signTransaction response', response);
                                const resultValue = extractResultValue(response);
                                if (!resultValue) {
                                    return [];
                                }
                                return [{
                                    signedTransaction: new Uint8Array(decodeBase58(resultValue)),
                                }];
                            },
                        },
                        'solana:signMessage': {
                            version: '1.0.0',
                            signMessage: async (input) => {
                                const id = ++this.lastGeneratedId;
                                const account = input?.account || this.accounts[0];
                                const address = account?.address || '';
                                if (!address) {
                                    return [];
                                }
                                const unifiedPayload = {
                                    id: String(id),
                                    chain: 'solana',
                                    payload: {
                                        url: window.origin,
                                        address,
                                        data: encodeBase58(input.message),
                                    },
                                };
                                const response = await this.request('signData', [unifiedPayload]);
                                const resultValue = extractResultValue(response);
                                if (!resultValue) {
                                    return [];
                                }
                                return [{
                                    signature: new Uint8Array(decodeBase58(resultValue)),
                                    signedMessage: input.message,
                                }];
                            },
                        },
                        'solana:signIn': {
                            version: '1.0.0',
                            signIn: async () => {
                                await Promise.resolve();
                                return [];
                            },
                        },
                    };
                }

                onDisconnect() {
                    ++this.lastGeneratedId;
                    this.accounts = [];
                    this.emit({ accounts: [] });
                }

                emit(data) {
                    this.listeners.forEach((listener) => {
                        try {
                            listener(data);
                        } catch (e) {}
                    });
                }

                request(name, args = []) {
                    return new Promise((resolve, reject) => window._mtwAir_invokeFunc('walletConnect:' + name, args, resolve, reject));
                }
            }

            const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" fill="none"><g clip-path="url(#a)"><path fill="url(#b)" d="M192 61a100 100 0 1 0 8 39 99 99 0 0 0-8-39m-8 80-5-12 11-6zM11 123l10 6-4 12zm-3-23v-9l8 9-8 9zm9-40 4 11-11 6zm173 17-11-6 5-12zm-54 86-8-6 8-5zm-23 8-6-8 9-2zm-25 0-3-10 9 2zm-6 6-13 8-4-14 13-9zm-18-14 1-11 8 5zm0-125 9 5-8 5zm24-9 6 8-9 2zm25 0 3 10-9-2zm5-6 13-8 5 14-13 9zm18 14v11l-8-5zm-36 119c-31 0-56-25-56-56a56 56 0 0 1 20-43h1l16-10h1a56 56 0 0 1 54 10 56 56 0 0 1 20 43c0 31-25 56-56 56m-63-51-10-5 10-5zm126-10 10 5-10 5zm-5-21 10 1-7 8zm-12-18 10-2-5 9zm-45-22L91 22l9-12 10 12zm-23 5L65 29l4-14 13 8zM49 63l-4-9 10 2zm-9 20-7-8h10zm-15-6 11 12-15 6-10-11zm-4 28 15 7-11 11-14-7zm19 13 3 8-10-1zm15 26-10 3 4-10zm46 22 9 12-10 12-9-12zm22-4 13 9-5 14-13-8zm28-25 5 10-11-3zm10-19 7 7-10 1zm15 5-11-11 14-7 10 11zm3-28-14-7 11-11 13 7zm-6-26-16-2 7-14 14 2zm-16-23-15 4 1-16 15-3zm-42-29-8-10 19 4zm-29 0-11-6 18-3zM58 50l-15-4V31l14 3zm-21 3 6 15-15 1-6-14zm-9 78 15 2-6 15-15-2zm15 23 15-3-1 16-14 3zm43 29 7 9-18-3zm29 0 11 6-19 4zm27-33 15 4 1 16-15-4zm22-3-7-14 16-2 5 15zm20-47 9-9v18zm-7-53-13-1 1-13zm-23-23-12 3-3-11zm-92-8-4 11-12-2zM36 33v13l-12 1zM24 153l12 1v13zm23 23 11-3 4 11zm92 8 3-11 12 3zm26-17-1-13 13-1z"/></g><defs><linearGradient id="b" x1="19.5" x2="228.5" y1="13" y2="78.2" gradientUnits="userSpaceOnUse"><stop stop-color="#71aaef"/><stop offset=".3" stop-color="#3f79cf"/><stop offset=".7" stop-color="#2e74b5"/><stop offset="1" stop-color="#2160a2"/></linearGradient><clipPath id="a"><path fill="#fff" d="M0 0h200v200H0z"/></clipPath></defs></svg>';

            const solanaWallet = new SolanaConnect();
            solanaWallet.icon = 'data:image/svg+xml,' + encodeURIComponent(svg);

            const register = (registerCallback) => {
                registerCallback.register(solanaWallet);
            };

            window.dispatchEvent(new CustomEvent('wallet-standard:register-wallet', { detail: register }));
            window.addEventListener('wallet-standard:request-provider', () => {
                window.dispatchEvent(new CustomEvent('wallet-standard:register-wallet', { detail: register }));
            });
            window.dispatchEvent(new CustomEvent('wallet-standard:app-ready', { detail: register }));

            const interval = setInterval(() => {
                window.dispatchEvent(new CustomEvent('wallet-standard:request-provider'));
                window.dispatchEvent(new CustomEvent('wallet-standard:register-wallet', { detail: register }));

                window.solana = {
                    isMyTonWallet: true,
                    publicKey: null,
                    isConnected: false,
                    connect: async (options) => {
                        const result = await solanaWallet.features['standard:connect'].connect(options);
                        if (result.accounts.length) {
                            const account = result.accounts[0];
                            window.solana.publicKey = account.publicKey;
                            window.solana.isConnected = true;
                            return { publicKey: account.publicKey };
                        }
                        return undefined;
                    },
                    disconnect: async () => {
                        await solanaWallet.features['standard:disconnect'].disconnect();
                        window.solana.isConnected = false;
                        window.solana.publicKey = null;
                    },
                    signTransaction: async (tx) => {
                        const res = await solanaWallet.features['solana:signTransaction'].signTransaction(tx);
                        return {
                            signedTransaction: res[0].signedTransaction,
                        };
                    },
                    on: (event, cb) => {
                        return solanaWallet.features['standard:events'].on(event, cb);
                    },
                };
            }, 500);

            setTimeout(() => clearInterval(interval), 10000);
        })();
        """
    }
}
