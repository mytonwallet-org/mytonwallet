/* eslint-disable no-console */
/**
 * Unlock a W5 mainnet wallet by removing the MFA extension via the on-chain contract (2FA required).
 *
 * This sends an external `op::remove_extension` to the MFA extension, signed with:
 * - seed signature (wallet mnemonic)
 * - Telegram signature (via MTKruto, same as miniapp)
 *
 * After success, the wallet:
 * - re-enables secret-key auth (`is_signature_allowed = true`)
 * - deletes the extension from its extensions dict
 * - extension self-destructs and returns its balance back to the wallet
 *
 * Usage:
 *   FUNDING_MNEMONIC="word1 ... word24" \\
 *   TELEGRAM_API_ID=... TELEGRAM_API_HASH=... \\
 *   node dev/mfa/unlock_mfa_wallet_mainnet.js
 *
 * Optional env:
 *   TARGET_WALLET_ADDRESS="UQ..."          # defaults to `UQAXt7U0...`
 *   MFA_EXTENSION_CODE_HASH="8cbd..."      # full code hash (hex), used for library-ref hash matching
 *   BOT_USERNAME="mtw_giveaway_bot"
 *   WEBAPP_URL="https://mfa-frontend.myinfra.dev/"
 */

const tonMnemonic = require('tonweb-mnemonic');
const childProcess = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const { TonClient, WalletContractV5R1 } = require('@ton/ton');
const {
  Address,
  beginCell,
  Cell,
  Dictionary,
  external,
  SendMode,
  storeMessageRelaxed,
} = require('@ton/core');
const { sign } = require('@ton/crypto');

const FUNDING_MNEMONIC_RAW = process.env.FUNDING_MNEMONIC;
const TARGET_WALLET_ADDRESS = process.env.TARGET_WALLET_ADDRESS || 'UQAXt7U0eHXLZhcngXzALAryEm_dtkTevqFfa2zc7UfcciR8';

const TELEGRAM_API_ID = process.env.TELEGRAM_API_ID;
const TELEGRAM_API_HASH = process.env.TELEGRAM_API_HASH;

const BOT_USERNAME = process.env.BOT_USERNAME || 'mtw_giveaway_bot';
const WEBAPP_URL = process.env.WEBAPP_URL || 'https://mfa-frontend.myinfra.dev/';

const MFA_EXTENSION_CODE_HASH = process.env.MFA_EXTENSION_CODE_HASH
  || '8cbd6c85088b82aa06567d2cd2c180f201eeb270a74ec6223f569298e5448234';

const TONCENTER_ENDPOINT = process.env.TONCENTER_ENDPOINT || 'https://toncenter.mytonwallet.org/api/v2/jsonRPC';
const TONCENTER_API_KEY = process.env.TONCENTER_API_KEY;

const NETWORK_GLOBAL_ID = -239; // W5 mainnet chain id used by MyTonWallet

const MTKRUTO_SIGN_SCRIPT = path.join(process.cwd(), 'trash', 'mtkruto', 'sign-payload.js');

const OpCode = {
  REMOVE_EXTENSION: 0xaeb09887,
};

function exitWithError(message) {
  console.error(message);
  process.exit(1);
}

function normalizeAddress(address) {
  return Address.parse(address).toString({ urlSafe: true, bounceable: false, testOnly: false });
}

function formatAddress(address, { bounceable = false } = {}) {
  return address.toString({
    urlSafe: true,
    bounceable,
    testOnly: false,
  });
}

async function sleep(ms) {
  await new Promise((r) => setTimeout(r, ms));
}

async function waitForWalletSignatureAllowed(opened, expected, { timeoutMs = 120_000, pollMs = 2_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const cur = await opened.getIsSecretKeyAuthEnabled();
    if (cur === expected) return;
    if (Date.now() > deadline) {
      throw new Error(`Timed out waiting for is_signature_allowed=${expected} (current=${cur})`);
    }
    await sleep(pollMs);
  }
}

function getContractCodeLibraryRefHash() {
  const libPrep = beginCell().storeUint(2, 8).storeBuffer(Buffer.from(MFA_EXTENSION_CODE_HASH, 'hex')).endCell();
  const cell = new Cell({ exotic: true, bits: libPrep.bits, refs: libPrep.refs });
  return cell.hash();
}

async function resolveMfaExtensionAddress(client, walletAddress) {
  const { stack, exit_code } = await client.runMethodWithError(walletAddress, 'get_extensions');
  if (exit_code !== 0) return undefined;

  const cell = stack.readCellOpt();
  if (!cell) return undefined;

  const dict = Dictionary.loadDirect(
    Dictionary.Keys.BigUint(256),
    Dictionary.Values.BigInt(1),
    cell,
  );
  const extensions = dict.keys().map((key) => Address.parseRaw(`0:${key.toString(16).padStart(64, '0')}`));

  const libraryRefHash = getContractCodeLibraryRefHash();
  const fullHash = Buffer.from(MFA_EXTENSION_CODE_HASH, 'hex');

  for (const ext of extensions) {
    const state = await client.getContractState(ext);
    if (!state.code) continue;
    const codeHash = Cell.fromBase64(state.code).hash();
    if (codeHash.equals(libraryRefHash) || codeHash.equals(fullHash)) return ext;
  }

  return undefined;
}

async function getExtensionSeqno(client, extensionAddress) {
  const { stack, exit_code } = await client.runMethodWithError(extensionAddress, 'get_seqno');
  if (exit_code !== 0) {
    throw new Error(`get_seqno failed (exit_code=${exit_code}). Extension is likely broken or missing library.`);
  }
  return Number(stack.readBigNumber());
}

function prepareBodyWithoutSignature({ opCode, seqno, payload }) {
  return beginCell()
    .storeUint(opCode, 32)
    .storeUint(seqno, 32)
    .storeRef(payload)
    .endCell();
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

  return {
    authDate: result.auth_date,
    signature: Buffer.from(result.signature, 'base64'),
  };
}

function getExternalMsgHashNormalized(message) {
  const cell = beginCell()
    .storeUint(2, 2) // Message type: external-in
    .storeUint(0, 2) // No sender address for external messages
    .storeAddress(message.info.dest) // Store recipient address
    .storeUint(0, 4) // Import fee is always zero for external messages
    .storeBit(false) // No StateInit in this message
    .storeBit(true) // Store the body as a reference
    .storeRef(message.body) // Store the message body
    .endCell();

  return cell.hash().toString('base64');
}

async function main() {
  if (!FUNDING_MNEMONIC_RAW) exitWithError('Missing env FUNDING_MNEMONIC (12/24 words).');

  const mnemonic = FUNDING_MNEMONIC_RAW.trim().split(/\s+/).filter(Boolean);
  if (mnemonic.length < 12) exitWithError('FUNDING_MNEMONIC looks invalid (expected 12/24 words).');

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

  const expected = normalizeAddress(TARGET_WALLET_ADDRESS);
  const actual = normalizeAddress(wallet.address.toString({ urlSafe: true, bounceable: false }));
  if (expected !== actual) {
    exitWithError(`Mnemonic wallet address mismatch. Expected ${expected}, got ${actual}.`);
  }

  console.log('Wallet:', formatAddress(wallet.address));

  const sigAllowed = await openedWallet.getIsSecretKeyAuthEnabled();
  console.log('Wallet is_signature_allowed:', sigAllowed);

  const walletAddress = Address.parse(TARGET_WALLET_ADDRESS);
  const ext = await resolveMfaExtensionAddress(client, walletAddress);
  if (!ext) exitWithError('Failed to resolve MFA extension address from wallet extensions dict.');

  console.log('MFA extension:', formatAddress(ext, { bounceable: true }));

  const extSeqno = await getExtensionSeqno(client, ext);
  console.log('Extension seqno:', extSeqno);

  const payload = prepareBodyWithoutSignature({
    opCode: OpCode.REMOVE_EXTENSION,
    seqno: extSeqno,
    payload: beginCell().endCell(),
  });
  const payloadHashB64 = payload.hash().toString('base64');
  const seedSignature = Buffer.from(sign(payload.hash(), Buffer.from(keyPair.secretKey)));

  console.log('Signing payload via Telegram (MTKruto) ...');
  const tg = getTelegramSignedPayload(payloadHashB64);

  const body = prepareExternalMessage({
    payload,
    seedSignature,
    telegramSignature: tg.signature,
    authDate: tg.authDate,
  });

  console.log('Sending remove_extension to MFA extension ...');
  await client.sendExternalMessage({ address: ext }, body);

  console.log('Waiting for wallet to re-enable secret-key auth ...');
  await waitForWalletSignatureAllowed(openedWallet, true);

  const txHash = getExternalMsgHashNormalized(external({ to: ext, body }));
  console.log('remove_extension external msg hash (normalized):', txHash);

  console.log('OK: wallet unlocked (secret-key auth enabled).');
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

