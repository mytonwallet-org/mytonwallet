# Source code review

This file is for reviewers who rebuild My Wallet from its source archive, such as the Firefox add-on review.

## Building

Requirements: any Linux or macOS with Node 24 and npm 11 (`engines` in `package.json` lists the accepted ranges).
The reviewer notes of each submitted version name the exact versions CI used.

```sh
npm ci
npm run extension-firefox:package
```

The result is `MyWallet-firefox.zip`. Every dependency outside `src/lib` comes from npm at the version locked in
`package-lock.json`.

## Third-party code in `src/lib`

These files are unmodified copies of a maintainer's release. The SHA-256 of each file equals that of the file at
the link.

| File | Library | Maintainer's release | SHA-256 |
|------|---------|----------------------|---------|
| `src/lib/aes-js/index.js` | aes-js 3.1.2 (MIT) | [ricmoo/aes-js v3.1.2](https://github.com/ricmoo/aes-js/blob/v3.1.2/index.js) | `579277f6e64049ff523b1fd6d6ce1bc9bd2b16b6253dac9862a02665e9bf103d` |
| `src/lib/big.js/index.js` | big.js 6.2.1 (MIT) | [MikeMcl/big.js v6.2.1, `big.mjs`](https://github.com/MikeMcl/big.js/blob/v6.2.1/big.mjs) | `ffdf344bed2a80d1566766461587c9d770c9285cb4a0f6b7a431a3063c0248cb` |
| `src/lib/big.js/LICENCE.md` | big.js 6.2.1 | [MikeMcl/big.js v6.2.1](https://github.com/MikeMcl/big.js/blob/v6.2.1/LICENCE.md) | `e375eb5dcbc7ef8a5646b27d20be31ddb70ec4021338fbe74efd5051a5aec519` |
| `src/lib/big.js/index.d.ts` | @types/big.js 6.1.6 (MIT) | [npm, `index.d.ts`](https://registry.npmjs.org/@types/big.js/-/big.js-6.1.6.tgz) | `2bcd9f3ac3b0ac799fcc507c899e1ef8b1ddd5b8914098ff93208139b3089930` |
| `src/lib/noble-ed25519/index.js` | @noble/ed25519 1.7.3 (MIT) | [paulmillr/noble-ed25519 release 1.7.3, `noble-ed25519.js`](https://github.com/paulmillr/noble-ed25519/releases/download/1.7.3/noble-ed25519.js) | `44f3b333d5e31f5a92bfd186707bfd2c3ed551e782ce1a131909944508ec6a80` |
| `src/lib/quantize.js` | quantize 1.0.2 (MIT) | [npm, `quantize.js`](https://registry.npmjs.org/quantize/-/quantize-1.0.2.tgz) | `93b15d7ce2b215f029bd95bc0f5cc8a7f1ad72e31e903bab223fcd9b62aed4f9` |

The build wraps the CommonJS and UMD files above into ES modules without changing them, see
`plugins/vendoredModules.ts`.

These are our TypeScript adaptations of third-party code. They are readable source compiled together with the
rest of the application.

| Directory | Based on | Our changes |
|-----------|----------|-------------|
| `src/lib/confusables` | [gc/confusables at `6dd35dc`](https://github.com/gc/confusables/tree/6dd35dcd601cad4481cfda940296d203fe89150f/src) (MIT, version 1.1.0) | `remove` renamed to `cleanText`, `obfuscate` and the exports we do not use removed |
| `src/lib/ed25519-hd-key` | [ed25519-hd-key 1.3.0](https://github.com/alepop/ed25519-hd-key) (MIT) | rewritten on top of `@noble/hashes` and `tweetnacl` from `package-lock.json` |
| `src/lib/solana-program` | the generated JavaScript clients of the [Solana Program Library](https://github.com/solana-program) and [mpl-token-metadata](https://github.com/metaplex-foundation/mpl-token-metadata) (Apache-2.0) | reduced to the instructions the wallet sends, on top of `@solana/kit` from `package-lock.json` |

## First-party code in `src/lib`

`blue-diamond`, `fasterdom`, `mediaWorker`, `offscreen-canvas`, `teact`, `tlottie` (except its `.wasm` files) and
`tonConnectFriendlyPatch.js` are our own code. `teact` and `fasterdom` started as a copy of the same modules of
[Telegram Web A](https://github.com/Ajaxy/telegram-tt).

## Compiled binaries

Both files are builds of [dkaraush/tlottie at `c461cd5`](https://github.com/dkaraush/tlottie/tree/c461cd5c295b1abb9b4e8cd62bd875d9b4d676e3)
(MIT), a Lottie renderer written in Rust. The worker loads the SIMD build where the browser supports WebAssembly
SIMD and the scalar build elsewhere.

| File | Build | SHA-256 |
|------|-------|---------|
| `src/lib/tlottie/tlottie-simd.wasm` | WebAssembly SIMD enabled | `719cc3627333687870f79f074c459e5a73e6602e0a7c89856be37dcfa2ba004b` |
| `src/lib/tlottie/tlottie-scalar.wasm` | without SIMD | `9cb035a1b3ebbc7aa4ebce557f8dc5a3c7e492a03f06617d8de596f730f9264b` |

To rebuild them on x86_64 Linux, install [rustup](https://rustup.rs) and run the commands below. The compiler on an
arm64 Mac produces different modules, so the binaries match only when built on x86_64 Linux.

```sh
mkdir /tmp/tlottie
bash deploy/tlottie_build.sh /tmp/tlottie
cmp /tmp/tlottie/tlottie-simd.wasm src/lib/tlottie/tlottie-simd.wasm
cmp /tmp/tlottie/tlottie-scalar.wasm src/lib/tlottie/tlottie-scalar.wasm
```

The script installs Rust 1.96.0 with the `wasm32-unknown-unknown` target, checks out the commit above and builds
its `wasm` feature with the size-optimized `release-size` profile. The modules have no JavaScript glue:
`src/lib/tlottie/tlottie.worker.ts` loads one with `WebAssembly.instantiate` and calls its exports directly.
