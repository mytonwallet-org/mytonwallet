/* eslint-disable no-console */
/**
 * End-to-end mainnet test for the MFA Extension using a real Telegram signature.
 *
 * Prereqs:
 * - `trash/TEST_WALLET_SEED.md` contains a W5 mnemonic (created by `dev/mfa/setup_test_wallet.js`).
 * - MTKruto sandbox is authorized and has `trash/mtkruto/session.json` (run `cd trash/mtkruto && npm run auth`).
 *
 * Usage:
 *   TELEGRAM_API_ID=... TELEGRAM_API_HASH=... node dev/mfa/test_mfa_extension_mainnet.js
 *
 * Optional env:
 *   TONCENTER_ENDPOINT="https://toncenter.mytonwallet.org/api/v2/jsonRPC"
 *   TONCENTER_API_KEY="..."
 *   MFA_EXTENSION_CODE_HASH="8cbd..." # full extension code hash (hex), used for library-ref code cell
 *   TELEGRAM_USER_ID="1368727604"     # optional sanity check for the current Telegram session
 *   BOT_USERNAME="mtw_giveaway_bot"
 *   WEBAPP_URL="https://mfa-frontend.myinfra.dev/"
 *   INSTALL_VALUE_TON="1"             # TON to send to extension on deploy/install
 *   ACTION_FEE_TON="0.03"             # TON to attach to the wallet request (paid from extension balance)
 *   DEST_ADDRESS="UQ..."              # recipient of the test transfer
 *   TRANSFER_TON="0.01"               # amount to transfer from wallet to DEST_ADDRESS
 */

const fs = require('node:fs');
const path = require('node:path');
const childProcess = require('node:child_process');
const crypto = require('node:crypto');

const tonMnemonic = require('tonweb-mnemonic');
const { TonClient, WalletContractV5R1 } = require('@ton/ton');
const {
  Address,
  beginCell,
  Cell,
  contractAddress,
  internal,
  SendMode,
  storeMessageRelaxed,
  toNano,
} = require('@ton/core');
const { sign } = require('@ton/crypto');

const TONCENTER_ENDPOINT = process.env.TONCENTER_ENDPOINT || 'https://toncenter.mytonwallet.org/api/v2/jsonRPC';
const TONCENTER_API_KEY = process.env.TONCENTER_API_KEY;

const TELEGRAM_API_ID = process.env.TELEGRAM_API_ID;
const TELEGRAM_API_HASH = process.env.TELEGRAM_API_HASH;

const TELEGRAM_USER_ID = process.env.TELEGRAM_USER_ID || '';
const BOT_USERNAME = process.env.BOT_USERNAME || 'mtw_giveaway_bot';
const WEBAPP_URL = process.env.WEBAPP_URL || 'https://mfa-frontend.myinfra.dev/';

const MFA_EXTENSION_CODE_HASH = process.env.MFA_EXTENSION_CODE_HASH
  || '8cbd6c85088b82aa06567d2cd2c180f201eeb270a74ec6223f569298e5448234';

const INSTALL_VALUE_TON = process.env.INSTALL_VALUE_TON || '1';
// Must be <= extension balance (it funds the internal wallet request).
const ACTION_FEE_TON = process.env.ACTION_FEE_TON || '0.03';
const TRANSFER_TON = process.env.TRANSFER_TON || '0.01';
const DEST_ADDRESS = process.env.DEST_ADDRESS || 'UQAXt7U0eHXLZhcngXzALAryEm_dtkTevqFfa2zc7UfcciR8';

const NETWORK_GLOBAL_ID = -239; // W5 mainnet chain id used by MyTonWallet

const SEED_FILE = path.join(process.cwd(), 'trash', 'TEST_WALLET_SEED.md');
const MTKRUTO_SIGN_SCRIPT = path.join(process.cwd(), 'trash', 'mtkruto', 'sign-payload.js');

const OpCode = {
  INSTALL: 0x43563174,
  SEND_ACTIONS: 0xb15f2c8c,
  REMOVE_EXTENSION: 0xaeb09887,
};

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

async function waitForSecretKeyAuthDisabled(opened, { timeoutMs = 120_000, pollMs = 2_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const enabled = await opened.getIsSecretKeyAuthEnabled();
    if (!enabled) return;
    if (Date.now() > deadline) throw new Error('Timed out waiting for secret key auth to be disabled');
    await sleep(pollMs);
  }
}

async function waitForSecretKeyAuthEnabled(opened, { timeoutMs = 120_000, pollMs = 2_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const enabled = await opened.getIsSecretKeyAuthEnabled();
    if (enabled) return;
    if (Date.now() > deadline) throw new Error('Timed out waiting for secret key auth to be enabled');
    await sleep(pollMs);
  }
}

async function getExtensionSeqno(client, extensionAddress) {
  const { stack } = await client.runMethod(extensionAddress, 'get_seqno');
  return Number(stack.readBigNumber());
}

function mfaExtensionConfigToCell({ telegramId, walletAddress, seedPubkey }) {
  return beginCell()
    .storeUint(0, 32)
    .storeAddress(walletAddress)
    .storeStringRefTail(String(telegramId))
    .storeBuffer(seedPubkey)
    .storeUint(0, 1 + 64)
    .endCell();
}

function getContractCodeLibraryRef() {
  const libPrep = beginCell().storeUint(2, 8).storeBuffer(Buffer.from(MFA_EXTENSION_CODE_HASH, 'hex')).endCell();
  return new Cell({ exotic: true, bits: libPrep.bits, refs: libPrep.refs });
}

function prepareBodyWithoutSignature({ opCode, seqno, payload }) {
  return beginCell()
    .storeUint(opCode, 32)
    .storeUint(seqno, 32)
    .storeRef(payload)
    .endCell();
}

function getBodyFromRequest(seqno, message) {
  const payload = beginCell()
    .storeUint(SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS, 8)
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

function execNodeJson(scriptPath, env) {
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
    throw new Error('Missing TELEGRAM_API_ID / TELEGRAM_API_HASH');
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

  if (TELEGRAM_USER_ID && result.telegram_id && String(result.telegram_id) !== String(TELEGRAM_USER_ID)) {
    throw new Error(`Telegram session mismatch: expected id=${TELEGRAM_USER_ID}, got id=${result.telegram_id}`);
  }

  return {
    telegramId: String(result.telegram_id || ''),
    authDate: result.auth_date,
    signature: Buffer.from(result.signature, 'base64'),
  };
}

function getTelegramIdFromSession() {
  const dummyHashB64 = crypto.randomBytes(32).toString('base64');
  const { telegramId } = getTelegramSignedPayload(dummyHashB64);
  if (!telegramId) {
    throw new Error('MTKruto signer did not return telegram_id (update trash/mtkruto/sign-payload.js)');
  }
  return telegramId;
}

async function main() {
  if (!fs.existsSync(SEED_FILE)) throw new Error(`Seed file not found: ${SEED_FILE}`);

  const seedFileContents = fs.readFileSync(SEED_FILE, 'utf8');
  const mnemonic = parseMnemonicFromFile(seedFileContents);
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

  console.log('Wallet:', formatAddress(wallet.address));
  console.log('Toncenter:', TONCENTER_ENDPOINT);
  console.log('Dest:', DEST_ADDRESS);

  const isSignatureAllowed = await openedWallet.getIsSecretKeyAuthEnabled();
  console.log('Wallet is_signature_allowed:', isSignatureAllowed);

  const walletBalance = await client.getBalance(wallet.address);
  console.log('Wallet balance (nano):', walletBalance.toString());

  const telegramId = getTelegramIdFromSession();

  const codeCell = getContractCodeLibraryRef();

  const dataCell = mfaExtensionConfigToCell({
    telegramId,
    walletAddress: wallet.address,
    seedPubkey: keyPair.publicKey,
  });
  const init = { code: codeCell, data: dataCell };
  const extensionAddress = contractAddress(0, init);

  console.log('Extension:', formatAddress(extensionAddress));
  console.log('Extension code hash (hex):', codeCell.hash().toString('hex'));

  // 1) Ensure extension is added to the wallet
  const extensions = await openedWallet.getExtensionsArray();
  const isAdded = extensions.some((a) => a.toRawString() === extensionAddress.toRawString());

  if (!isAdded) {
    if (!isSignatureAllowed) {
      throw new Error('Wallet is locked (signature disabled) and does not have the expected extension in its dict. Only recovery can help.');
    }
    const seqno = await openedWallet.getSeqno();
    console.log('Adding extension to wallet (seqno', seqno, ') ...');
    await openedWallet.sendAddExtension({
      authType: 'external',
      seqno,
      secretKey: keyPair.secretKey,
      extensionAddress,
    });
    await waitForWalletSeqnoBump(openedWallet, seqno);
  } else {
    console.log('Extension already added to wallet.');
  }

  // 2) Deploy/install extension if needed
  const isDeployed = await client.isContractDeployed(extensionAddress);
  if (!isDeployed) {
    if (!isSignatureAllowed) {
      throw new Error('Wallet is locked (signature disabled) and extension is not deployed. Only recovery can help.');
    }
    const seqno = await openedWallet.getSeqno();
    console.log('Deploying/installing extension (seqno', seqno, ') ...');
    await openedWallet.sendTransfer({
      authType: 'external',
      seqno,
      secretKey: keyPair.secretKey,
      messages: [
        internal({
          to: extensionAddress,
          value: toNano(INSTALL_VALUE_TON),
          bounce: false,
          init,
          body: beginCell().storeUint(OpCode.INSTALL, 32).endCell(),
        }),
      ],
    });
    await waitForWalletSeqnoBump(openedWallet, seqno);

    // Wait until the contract is actually on-chain
    const deadline = Date.now() + 120_000;
    // eslint-disable-next-line no-constant-condition
    while (true) {
      if (await client.isContractDeployed(extensionAddress)) break;
      if (Date.now() > deadline) throw new Error('Timed out waiting for extension deploy');
      await sleep(2_000);
    }
  } else {
    console.log('Extension already deployed.');
  }

  // 3) Wait until wallet disables secret key auth (install handshake)
  console.log('Waiting for wallet to disable secret key auth ...');
  await waitForSecretKeyAuthDisabled(openedWallet);

  // 4) Build a test "send actions" request for the extension
  const extensionSeqno = await getExtensionSeqno(client, extensionAddress);
  const walletSeqno = await openedWallet.getSeqno();
  console.log('Extension seqno:', extensionSeqno);
  console.log('Wallet seqno:', walletSeqno);

  const dest = Address.parseFriendly(DEST_ADDRESS).address;
  const transferAmount = toNano(TRANSFER_TON);
  const requestFee = toNano(ACTION_FEE_TON);

  const destBalBefore = await client.getBalance(dest);

  const outMsg = internal({
    to: dest,
    value: transferAmount,
    bounce: false,
  });

  const msgToWallet = internal({
    to: wallet.address,
    value: requestFee,
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
  const payloadHash = payload.hash();
  const payloadHashB64 = payloadHash.toString('base64');

  const seedSignature = sign(payloadHash, Buffer.from(keyPair.secretKey));
  const tg = getTelegramSignedPayload(payloadHashB64);

  const externalBody = prepareExternalMessage({
    payload,
    seedSignature,
    telegramSignature: tg.signature,
    authDate: tg.authDate,
  });

  console.log('Sending external request to extension ...');
  await client.sendExternalMessage({ address: extensionAddress }, externalBody);

  await waitForExtensionSeqno(client, extensionAddress, extensionSeqno + 1);

  // Best-effort: wait a bit for the wallet to execute and recipient balance to reflect.
  await sleep(8_000);
  const destBalAfter = await client.getBalance(dest);

  console.log('Recipient balance before (nano):', destBalBefore.toString());
  console.log('Recipient balance after  (nano):', destBalAfter.toString());

  if (destBalAfter <= destBalBefore) {
    throw new Error('Recipient balance did not increase (transfer may have failed)');
  }

  console.log('OK: extension signed transaction executed.');

  // 5) Remove extension (disconnect)
  const removeSeqno = await getExtensionSeqno(client, extensionAddress);
  console.log('Removing extension (seqno', removeSeqno, ') ...');

  const removePayload = prepareBodyWithoutSignature({
    opCode: OpCode.REMOVE_EXTENSION,
    seqno: removeSeqno,
    payload: beginCell().endCell(),
  });

  const removePayloadHashB64 = removePayload.hash().toString('base64');
  const removeSeedSignature = sign(removePayload.hash(), Buffer.from(keyPair.secretKey));
  const removeTg = getTelegramSignedPayload(removePayloadHashB64);

  const removeExternalBody = prepareExternalMessage({
    payload: removePayload,
    seedSignature: removeSeedSignature,
    telegramSignature: removeTg.signature,
    authDate: removeTg.authDate,
  });

  await client.sendExternalMessage({ address: extensionAddress }, removeExternalBody);

  console.log('Waiting for wallet to re-enable secret key auth ...');
  await waitForSecretKeyAuthEnabled(openedWallet);

  const extensionsAfter = await openedWallet.getExtensionsArray();
  const stillPresent = extensionsAfter.some((a) => a.toRawString() === extensionAddress.toRawString());
  if (stillPresent) {
    throw new Error('Extension is still present in wallet extensions dict after remove_extension');
  }

  console.log('OK: extension removed and wallet unlocked.');
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
