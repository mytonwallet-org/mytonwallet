/* eslint-disable no-console */
/**
 * Publish the MFA Extension code as a public on-chain library (TON mainnet)
 * using the `LibDeployer` contract from `mfa-extension`.
 *
 * This is REQUIRED for MyTonWallet client builds that use a library-ref exotic
 * code cell for the extension (see `getContractCode()` in wallet client).
 *
 * It saves a record to `trash/MFA_EXTENSION_LIBRARY.md`.
 *
 * Usage:
 *   node dev/mfa/deploy_mfa_extension_library_mainnet.js
 *
 * Optional env:
 *   TONCENTER_ENDPOINT="https://toncenter.mytonwallet.org/api/v2/jsonRPC"
 *   TONCENTER_API_KEY="..."
 *   LIB_DEPLOY_VALUE_TON="0.5"        # value sent to LibDeployer (stays on that account)
 *   WALLET_REQUEST_FEE_TON="0.5"      # value sent from extension -> wallet to cover fees
 *   TELEGRAM_API_ID=...
 *   TELEGRAM_API_HASH=...
 *   BOT_USERNAME="mtw_giveaway_bot"
 *   WEBAPP_URL="https://mfa-frontend.myinfra.dev/"
 */

const fs = require('node:fs');
const path = require('node:path');
const fsp = require('node:fs/promises');

const tonMnemonic = require('tonweb-mnemonic');
const { TonClient, WalletContractV5R1 } = require('@ton/ton');
const { beginCell, Cell, contractAddress, internal, toNano } = require('@ton/core');

const TONCENTER_ENDPOINT = process.env.TONCENTER_ENDPOINT || 'https://toncenter.mytonwallet.org/api/v2/jsonRPC';
const TONCENTER_API_KEY = process.env.TONCENTER_API_KEY;

const LIB_DEPLOY_VALUE_TON = process.env.LIB_DEPLOY_VALUE_TON || '0.5';
const WALLET_REQUEST_FEE_TON = process.env.WALLET_REQUEST_FEE_TON || '0.5';

const TELEGRAM_API_ID = process.env.TELEGRAM_API_ID;
const TELEGRAM_API_HASH = process.env.TELEGRAM_API_HASH;
const BOT_USERNAME = process.env.BOT_USERNAME || 'mtw_giveaway_bot';
const WEBAPP_URL = process.env.WEBAPP_URL || 'https://mfa-frontend.myinfra.dev/';

const NETWORK_GLOBAL_ID = -239; // W5 mainnet chain id used by MyTonWallet

const SEED_FILE = path.join(process.cwd(), 'trash', 'TEST_WALLET_SEED.md');
const OUT_FILE = path.join(process.cwd(), 'trash', 'MFA_EXTENSION_LIBRARY.md');

const EXT_COMPILED_JSON = path.resolve(__dirname, '../../..', 'mfa-extension', 'build', 'MfaExtension.compiled.json');
const DEPLOYER_COMPILED_JSON = path.resolve(__dirname, '../../..', 'mfa-extension', 'build', 'LibDeployer.compiled.json');
const MTKRUTO_SIGN_SCRIPT = path.join(process.cwd(), 'trash', 'mtkruto', 'sign-payload.js');

function parseMnemonicFromFile(contents) {
  const match = contents.match(/Mnemonic:\s*(.+)/i);
  if (!match) return undefined;
  const words = match[1].trim().split(/\s+/).filter(Boolean);
  return words.length >= 12 ? words : undefined;
}

function formatAddress(address, { testOnly = false } = {}) {
  return address.toString({
    urlSafe: true,
    bounceable: false,
    testOnly,
  });
}

async function sleep(ms) {
  await new Promise((r) => setTimeout(r, ms));
}

async function waitForWalletSeqnoBump(opened, prev, { timeoutMs = 120_000, pollMs = 2_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const current = await opened.getSeqno();
    if (current > prev) return current;
    if (Date.now() > deadline) throw new Error(`Timed out waiting for wallet seqno bump (prev=${prev}, current=${current})`);
    await sleep(pollMs);
  }
}

async function toncenterGetLibraries(hashesBase64, { endpoint }) {
  const res = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: 1,
      method: 'getLibraries',
      params: { libraries: hashesBase64 },
    }),
  });
  const body = await res.json();
  if (!body.ok) {
    throw new Error(`getLibraries failed: ${body.error || JSON.stringify(body)}`);
  }
  return body.result;
}

function execNodeJson(scriptPath, env) {
  const childProcess = require('node:child_process');

  const stdout = childProcess.execFileSync(
    process.execPath,
    [scriptPath],
    {
      env,
      stdio: ['ignore', 'pipe', 'inherit'],
      maxBuffer: 10 * 1024 * 1024,
    },
  ).toString('utf8').trim();

  return JSON.parse(stdout);
}

function getTelegramSignedPayload(payloadHashB64) {
  if (!TELEGRAM_API_ID || !TELEGRAM_API_HASH) {
    throw new Error('Missing TELEGRAM_API_ID / TELEGRAM_API_HASH (required when wallet secret-key auth is disabled)');
  }
  if (!fs.existsSync(MTKRUTO_SIGN_SCRIPT)) {
    throw new Error(`Missing MTKruto sign script: ${MTKRUTO_SIGN_SCRIPT}`);
  }

  const result = execNodeJson(MTKRUTO_SIGN_SCRIPT, {
    ...process.env,
    TELEGRAM_API_ID,
    TELEGRAM_API_HASH,
    BOT_USERNAME,
    WEBAPP_URL,
    PAYLOAD_B64: payloadHashB64,
  });

  return {
    authDate: result.auth_date,
    signature: Buffer.from(result.signature, 'base64'),
  };
}

async function getExtensionSeqno(client, extensionAddress) {
  const { stack } = await client.runMethod(extensionAddress, 'get_seqno');
  return Number(stack.readBigNumber());
}

function prepareBodyWithoutSignature({ opCode, seqno, payload }) {
  return beginCell()
    .storeUint(opCode, 32)
    .storeUint(seqno, 32)
    .storeRef(payload)
    .endCell();
}

function getBodyFromRequest(seqno, message, { storeSendMode = true } = {}) {
  const { storeMessageRelaxed, SendMode } = require('@ton/core');

  const payload = beginCell()
    .storeUint(storeSendMode ? SendMode.PAY_GAS_SEPARATELY : 0, 8)
    .storeRef(beginCell().store(storeMessageRelaxed(message)).endCell())
    .endCell();

  return prepareBodyWithoutSignature({ opCode: OpCode.SEND_ACTIONS, payload, seqno });
}

function prepareExternalMessage({ payload, seedSignature, telegramSignature, authDate }) {
  return beginCell()
    .storeRef(beginCell().storeBuffer(seedSignature).endCell())
    .storeStringRefTail(String(authDate))
    .storeSlice(payload.beginParse())
    .storeBuffer(telegramSignature)
    .endCell();
}

async function waitForExtensionSeqno(client, address, expected, { timeoutMs = 120_000, pollMs = 2_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const seqno = await getExtensionSeqno(client, address);
    if (seqno >= expected) return seqno;
    if (Date.now() > deadline) throw new Error(`Timed out waiting for extension seqno >= ${expected} (current=${seqno})`);
    await sleep(pollMs);
  }
}

const OpCode = {
  SEND_ACTIONS: 0xb15f2c8c,
};

async function main() {
  if (!fs.existsSync(SEED_FILE)) throw new Error(`Seed file not found: ${SEED_FILE}`);
  if (!fs.existsSync(EXT_COMPILED_JSON)) throw new Error(`Missing compiled extension: ${EXT_COMPILED_JSON}`);
  if (!fs.existsSync(DEPLOYER_COMPILED_JSON)) throw new Error(`Missing compiled deployer: ${DEPLOYER_COMPILED_JSON}`);

  const mnemonicFile = fs.readFileSync(SEED_FILE, 'utf8');
  const mnemonic = parseMnemonicFromFile(mnemonicFile);
  if (!mnemonic) throw new Error(`Failed to parse mnemonic from: ${SEED_FILE}`);

  const keyPair = await tonMnemonic.mnemonicToKeyPair(mnemonic);

  const client = new TonClient({
    endpoint: TONCENTER_ENDPOINT,
    ...(TONCENTER_API_KEY ? { apiKey: TONCENTER_API_KEY } : {}),
  });

  const wallet = WalletContractV5R1.create({
    publicKey: keyPair.publicKey,
    workchain: 0,
    walletId: { networkGlobalId: NETWORK_GLOBAL_ID },
  });
  const openedWallet = client.open(wallet);

  const extCompiled = JSON.parse(fs.readFileSync(EXT_COMPILED_JSON, 'utf8'));
  const deployerCompiled = JSON.parse(fs.readFileSync(DEPLOYER_COMPILED_JSON, 'utf8'));

  const extensionCode = Cell.fromBoc(Buffer.from(extCompiled.hex, 'hex'))[0];
  const deployerCode = Cell.fromBoc(Buffer.from(deployerCompiled.hex, 'hex'))[0];

  const libHashHex = extensionCode.hash().toString('hex');
  const libHashB64 = Buffer.from(libHashHex, 'hex').toString('base64');

  const init = { code: deployerCode, data: extensionCode };
  const deployerAddress = contractAddress(-1, init);

  console.log('Deployer wallet:', formatAddress(wallet.address));
  console.log('LibDeployer address:', formatAddress(deployerAddress));
  console.log('Library code hash (hex):', libHashHex);
  console.log('Toncenter:', TONCENTER_ENDPOINT);

  const before = await toncenterGetLibraries([libHashB64], { endpoint: TONCENTER_ENDPOINT });
  const alreadyPublished = Array.isArray(before.result) && before.result.length > 0;

  if (!alreadyPublished) {
    const isSecretKeyAuthEnabled = await openedWallet.getIsSecretKeyAuthEnabled();
    console.log('Wallet secret-key auth enabled:', isSecretKeyAuthEnabled);

    if (isSecretKeyAuthEnabled) {
      const seqno = await openedWallet.getSeqno();
      console.log('Publishing library via wallet external auth (seqno', seqno, ') ...');

      await openedWallet.sendTransfer({
        authType: 'external',
        seqno,
        secretKey: keyPair.secretKey,
        messages: [
          internal({
            to: deployerAddress,
            value: toNano(LIB_DEPLOY_VALUE_TON),
            bounce: false,
            init,
            body: beginCell().endCell(),
          }),
        ],
      });

      await waitForWalletSeqnoBump(openedWallet, seqno);
    } else {
      // Wallet is MFA-locked: publish library via the installed MFA extension.
      const extensions = await openedWallet.getExtensionsArray();
      if (!extensions.length) {
        throw new Error('Wallet has secret-key auth disabled but no extensions were found.');
      }
      const extensionAddress = extensions[0];
      console.log('Using MFA extension:', formatAddress(extensionAddress));

      const extensionSeqno = await getExtensionSeqno(client, extensionAddress);
      const walletSeqno = await openedWallet.getSeqno();
      console.log('Extension seqno:', extensionSeqno);
      console.log('Wallet seqno:', walletSeqno);

      const { SendMode } = require('@ton/core');

      const outMsg = internal({
        to: deployerAddress,
        value: toNano(LIB_DEPLOY_VALUE_TON),
        bounce: false,
        init,
        body: beginCell().endCell(),
      });

      const msgToWallet = internal({
        to: wallet.address,
        value: toNano(WALLET_REQUEST_FEE_TON),
        body: wallet.createRequest({
          authType: 'extension',
          seqno: walletSeqno,
          actions: [
            {
              type: 'sendMsg',
              mode: SendMode.PAY_GAS_SEPARATELY,
              outMsg,
            },
          ],
        }),
      });

      const payload = getBodyFromRequest(extensionSeqno, msgToWallet);
      const payloadHashB64 = payload.hash().toString('base64');

      const seedSignature = Buffer.from(require('@ton/crypto').sign(payload.hash(), Buffer.from(keyPair.secretKey)));
      const tg = getTelegramSignedPayload(payloadHashB64);

      const extBody = prepareExternalMessage({
        payload,
        seedSignature,
        telegramSignature: tg.signature,
        authDate: tg.authDate,
      });

      console.log('Sending external message to MFA extension to publish library ...');
      await client.sendExternalMessage({ address: extensionAddress }, extBody);
      await waitForExtensionSeqno(client, extensionAddress, extensionSeqno + 1);
    }
  } else {
    console.log('Library already published.');
  }

  // Verify library availability (best-effort; toncenter should now return it)
  const verifyDeadline = Date.now() + 30_000;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const after = await toncenterGetLibraries([libHashB64], { endpoint: TONCENTER_ENDPOINT });
    const ok = Array.isArray(after.result) && after.result.length > 0;
    if (ok) break;
    if (Date.now() > verifyDeadline) {
      throw new Error('Library still not visible via getLibraries after publish. Check toncenter / network.');
    }
    await sleep(1_000);
  }

  const now = new Date().toISOString();
  const contents = [
    '# MFA Extension Library (mainnet)',
    '',
    `Saved: ${now}`,
    `Library code hash (hex): ${libHashHex}`,
    `Library code hash (base64): ${libHashB64}`,
    `LibDeployer address: ${formatAddress(deployerAddress)}`,
    `Deployer wallet: ${formatAddress(wallet.address)}`,
    `Toncenter: ${TONCENTER_ENDPOINT}`,
    '',
    'Use in wallet env:',
    `MFA_EXTENSION_CODE_HASH=${libHashHex}`,
    '',
  ].join('\n');

  await fsp.mkdir(path.dirname(OUT_FILE), { recursive: true });
  await fsp.writeFile(OUT_FILE, contents, 'utf8');

  console.log('Saved:', OUT_FILE);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
