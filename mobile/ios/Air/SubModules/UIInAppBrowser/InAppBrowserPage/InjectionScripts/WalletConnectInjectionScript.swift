import Foundation
import WalletContext

private var walletConnectInstallFlag: String {
    IS_GRAM_WALLET ? "__gramWalletSolanaConnectorInstalled" : "__mtwSolanaConnectorInstalled"
}

private var walletConnectConsolePrefix: String {
    IS_GRAM_WALLET ? "gramwallet.solana" : "mtw.solana"
}

var injectedWalletIconSvg: String {
    if IS_GRAM_WALLET {
        return ##"`<svg width="512" height="512" viewBox="0 0 512 512" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="512" height="512" fill="#2196F3"/><rect width="512" height="512" fill="url(#paint0_linear_12_2482)" fill-opacity="0.14" style="mix-blend-mode:plus-lighter"/><path fill-rule="evenodd" clip-rule="evenodd" d="M306.212 125.099C325.272 125.099 334.808 125.1 343.429 127.765C351.058 130.124 358.136 133.99 364.245 139.132C371.148 144.941 376.307 152.953 386.612 168.982L413.029 210.099C420.933 222.394 424.889 228.546 425.962 235.015C426.906 240.719 426.281 246.576 424.145 251.949C421.722 258.041 416.546 263.215 406.212 273.549L284.962 394.799C274.826 404.934 269.755 410.015 263.912 411.915C258.77 413.586 253.22 413.586 248.079 411.915C242.234 410.015 237.165 404.935 227.029 394.799L105.779 273.549C95.445 263.215 90.2684 258.041 87.8452 251.949C85.7094 246.576 85.0842 240.719 86.0285 235.015C87.1013 228.546 91.0577 222.394 98.9619 210.099L125.379 168.982C135.683 152.953 140.843 144.941 147.745 139.132C153.855 133.99 160.932 130.124 168.562 127.765C177.182 125.1 186.719 125.099 205.779 125.099H306.212ZM278.229 210.615L223.745 230.782L278.229 250.932L298.379 305.415L318.529 250.932L373.012 230.782L318.529 210.615L298.379 156.149L278.229 210.615Z" fill="white"/><defs><linearGradient id="paint0_linear_12_2482" x1="256" y1="0" x2="256" y2="512" gradientUnits="userSpaceOnUse"><stop stop-color="white"/><stop offset="1" stop-color="white" stop-opacity="0"/></linearGradient></defs></svg>`"##
    }
    return ##"`<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" fill="none"><g clip-path="url(#logoLight_svg__a)"><rect width="512" height="512" fill="url(#logoLight_svg__b)" rx="256"/><path fill="#fff" fill-opacity=".75" d="M151.218 180.762c-7.1 3.282-10.65 4.923-13.18 6.978a26 26 0 0 0-8.782 26.663c.813 3.156 2.693 6.586 6.453 13.445l42.041 76.685 34.449 62.838c2.868 5.231 4.396 8.017 6.083 10.035l.039.046q.157.188.318.366a24 24 0 0 0 22.754 7.495c2.698-.559 5.594-1.898 11.388-4.576 7.101-3.281 10.651-4.922 13.18-6.978a26 26 0 0 0 8.782-26.662c-.813-3.156-2.693-6.586-6.453-13.445l-42.04-76.684-34.45-62.839c-2.865-5.227-4.393-8.005-6.079-10.023l-.029-.035c-.11-.132-.22-.265-.331-.39a24 24 0 0 0-22.754-7.494c-2.698.559-5.595 1.898-11.389 4.575m107.997-49.496c-7.101 3.281-10.651 4.922-13.18 6.978a26 26 0 0 0-8.783 26.662c.813 3.157 2.693 6.586 6.454 13.445l42.04 76.685 34.449 62.838c2.868 5.231 4.396 8.017 6.083 10.035l.039.047q.158.188.318.366a24 24 0 0 0 22.754 7.495c2.698-.559 5.595-1.898 11.389-4.576 7.1-3.282 10.65-4.923 13.18-6.978a26 26 0 0 0 8.782-26.662c-.813-3.157-2.693-6.586-6.454-13.445l-42.04-76.685-34.449-62.838c-2.866-5.228-4.393-8.006-6.079-10.024l-.03-.035c-.109-.131-.22-.265-.331-.389a24 24 0 0 0-22.754-7.495c-2.698.559-5.595 1.898-11.388 4.576"/><g fill="#fff" filter="url(#logoLight_svg__c)"><path fill-rule="evenodd" d="m185.692 184.071-.039-.047zM183 182.532l.01.002z" clip-rule="evenodd"/><path d="M118.25 512h59.5V186.97a4.5 4.5 0 0 1 5.25-4.438l.01.002a4 4 0 0 1 .508.117q.08.023.156.049a4.5 4.5 0 0 1 1.979 1.324q-.145-.176-.292-.343a24 24 0 0 0-22.754-7.494c-2.698.559-5.595 1.898-11.389 4.575l-.002.001-1.656.766-1.223.565-.006.003-.003.002c-6.612 3.055-9.918 4.583-12.697 6.489a40 40 0 0 0-16.817 26.299c-.564 3.322-.564 6.964-.564 14.248z"/></g><g fill="#fff" filter="url(#logoLight_svg__d)"><path fill-rule="evenodd" d="M291.804 133.25a4.5 4.5 0 0 1 1.884 1.324l-.039-.047a4.5 4.5 0 0 0-1.845-1.277" clip-rule="evenodd"/><path d="M285.749 332.365V151.413c0-1.086 0-2.082-.003-2.998v-10.942a4.5 4.5 0 0 1 5.25-4.437l.01.001a6 6 0 0 1 .466.105q.168.048.332.108a4.5 4.5 0 0 1 1.845 1.277c-.097-.116-.194-.233-.292-.342a24 24 0 0 0-22.754-7.495c-2.698.559-5.595 1.898-11.389 4.576l-.69.319q-1.024.471-2.196 1.013l-.001.001c-6.612 3.055-9.918 4.583-12.697 6.489a40 40 0 0 0-16.817 26.299c-.564 3.322-.564 6.964-.564 14.248V374.53a4.5 4.5 0 0 1-4.5 4.5 4.49 4.49 0 0 1-3.429-1.578q.158.188.318.366a24 24 0 0 0 22.754 7.495c2.698-.559 5.595-1.898 11.388-4.576l.006-.002 1.428-.66 1.342-.62.103-.048.013-.006c6.612-3.056 9.918-4.583 12.696-6.489a40 40 0 0 0 16.818-26.299c.563-3.322.563-6.964.563-14.248"/></g><g filter="url(#logoLight_svg__e)"><path fill="#fff" d="M393.749 282.865V0h-59.5v207.478l-.004-.007v117.562a4.5 4.5 0 0 1-4.5 4.5 4.49 4.49 0 0 1-3.429-1.577q.158.188.318.366a24 24 0 0 0 22.754 7.495c2.698-.559 5.595-1.898 11.389-4.576l2.362-1.094.533-.246c6.611-3.055 9.918-4.583 12.696-6.489a40 40 0 0 0 16.818-26.299c.563-3.322.563-6.964.563-14.248"/></g></g><defs><filter id="logoLight_svg__c" width="115.442" height="384.313" x="102.25" y="153.687" color-interpolation-filters="sRGB" filterUnits="userSpaceOnUse"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feColorMatrix in="SourceAlpha" result="hardAlpha" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"/><feOffset dx="8" dy="2"/><feGaussianBlur stdDeviation="12"/><feComposite in2="hardAlpha" operator="out"/><feColorMatrix values="0 0 0 0 0 0 0 0 0 0.403922 0 0 0 0 0.976471 0 0 0 0.3 0"/><feBlend in2="BackgroundImageFix" result="effect1_dropShadow_49962_36143"/><feBlend in="SourceGraphic" in2="effect1_dropShadow_49962_36143" result="shape"/></filter><filter id="logoLight_svg__d" width="123.368" height="307.623" x="202.32" y="104.19" color-interpolation-filters="sRGB" filterUnits="userSpaceOnUse"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feColorMatrix in="SourceAlpha" result="hardAlpha" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"/><feOffset dx="8" dy="2"/><feGaussianBlur stdDeviation="12"/><feComposite in2="hardAlpha" operator="out"/><feColorMatrix values="0 0 0 0 0 0 0 0 0 0.403922 0 0 0 0 0.976471 0 0 0 0.3 0"/><feBlend in2="BackgroundImageFix" result="effect1_dropShadow_49962_36143"/><feBlend in="SourceGraphic" in2="effect1_dropShadow_49962_36143" result="shape"/></filter><filter id="logoLight_svg__e" width="115.433" height="384.317" x="310.316" y="-22" color-interpolation-filters="sRGB" filterUnits="userSpaceOnUse"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feColorMatrix in="SourceAlpha" result="hardAlpha" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"/><feOffset dx="8" dy="2"/><feGaussianBlur stdDeviation="12"/><feComposite in2="hardAlpha" operator="out"/><feColorMatrix values="0 0 0 0 0 0 0 0 0 0.403922 0 0 0 0 0.976471 0 0 0 0.3 0"/><feBlend in2="BackgroundImageFix" result="effect1_dropShadow_49962_36143"/><feBlend in="SourceGraphic" in2="effect1_dropShadow_49962_36143" result="shape"/></filter><linearGradient id="logoLight_svg__b" x1="256" x2="256" y1="0" y2="512" gradientUnits="userSpaceOnUse"><stop stop-color="#00b7ff"/><stop offset="1" stop-color="#0067f9"/></linearGradient><clipPath id="logoLight_svg__a"><rect width="512" height="512" fill="#fff" rx="256"/></clipPath></defs></svg>`"##
}

struct WalletConnectInjectionScript {
    static let source = """
        (function() {
            if (window.\(walletConnectInstallFlag)) return;
            window.\(walletConnectInstallFlag) = true;

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
                    this.name = '\(APP_NAME)';
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
                                            chains: [`${e.chain}:${e.network === 'mainnet' ? 'mainnet' : 'devnet'}`],
                                            features: Object.keys(this.features),
                                        }));
                                        this.accounts = standardWalletAddresses;
                                        return { accounts: this.accounts };
                                    }
                                    const metadata = {
                                        url: window.origin,
                                        name: (document.querySelector('meta[property*="og:title"]') || {}).content || document.title,
                                        description: '',
                                        icons: [(document.querySelector('link[rel*="icon"]') || {}).href || `${window.location.origin}/favicon.ico` || ''],
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
                                        chains: [`${e.chain}:${e.network === 'mainnet' ? 'mainnet' : 'devnet'}`],
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
                                    console.log('\(walletConnectConsolePrefix) signAndSendTransaction invalid input', { address, hasTx: !!txBytes });
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
                                console.log('\(walletConnectConsolePrefix) signAndSendTransaction response', response);
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
                                    console.log('\(walletConnectConsolePrefix) signTransaction invalid input', { address, hasTx: !!txBytes });
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
                                console.log('\(walletConnectConsolePrefix) signTransaction response', response);
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
                    window._mtwAir_eventListeners.push((event) => {
                        if (event && event.event === 'disconnect') {
                            this.onDisconnect();
                        }
                    });
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
                    return new Promise((resolve, reject) => window._mtwAir_invokeFunc(`walletConnect:${name}`, args, resolve, reject));
                }
            }

            const svg = \(injectedWalletIconSvg);

            const solanaWallet = new SolanaConnect();
            solanaWallet.icon = `data:image/svg+xml,${encodeURIComponent(svg)}`;

            const register = (registerCallback) => {
                registerCallback.register(solanaWallet);
            };

            window.dispatchEvent(new CustomEvent('wallet-standard:register-wallet', { detail: register }));
            window.addEventListener('wallet-standard:request-provider', () => {
                window.dispatchEvent(new CustomEvent('wallet-standard:register-wallet', { detail: register }));
            });
            window.dispatchEvent(new CustomEvent('wallet-standard:app-ready', { detail: register }));

            if (!window.solana) {
                window.solana = {
                    isMyTonWallet: \(!IS_GRAM_WALLET),
                    isGramWallet: \(IS_GRAM_WALLET),
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
                    signAllTransactions: async (txs) => {
                        const signedTransactions = await Promise.all(txs.map(async (tx) => {
                            const res = await solanaWallet.features['solana:signTransaction'].signTransaction(tx);
                            return res[0]?.signedTransaction;
                        }));
                        return { signedTransactions };
                    },
                    on: (event, cb) => {
                        return solanaWallet.features['standard:events'].on(event, cb);
                    },
                };
            }

            const interval = setInterval(() => {
                window.dispatchEvent(new CustomEvent('wallet-standard:register-wallet', { detail: register }));
                window.dispatchEvent(new CustomEvent('wallet-standard:request-provider'));
            }, 500);

            setTimeout(() => clearInterval(interval), 10000);
        })();
        """
}
