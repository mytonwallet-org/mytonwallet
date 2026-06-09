/* eslint-disable no-console */
/**
 * End-to-end mainnet MFA flow test against the deployed backend:
 * 1) Build an MFA payload + seed signature (wallet owner signature)
 * 2) POST it to `mfa-server` `/transaction` (server validates signature)
 * 3) Fetch the stored request back
 * 4) Obtain a real Telegram signature via MTKruto (same as miniapp does)
 * 5) Send external message to the on-chain MFA Extension
 * 6) Confirm the request on backend and verify it becomes confirmed
 *
 * Prereqs:
 * - `trash/TEST_WALLET_SEED.md` contains a W5 mnemonic.
 * - The wallet has the MFA Extension installed + funded.
 * - MTKruto sandbox is authorized and has `trash/mtkruto/session.json`.
 *
 * Usage:
 *   TELEGRAM_API_ID=... TELEGRAM_API_HASH=... node dev/mfa/test_mfa_server_flow_mainnet.js
 *
 * Optional env:
 *   MFA_API_BASE_URL="https://mfa-server.myinfra.dev"
 *   TONCENTER_ENDPOINT="https://toncenter.mytonwallet.org/api/v2/jsonRPC"
 *   TONCENTER_API_KEY="..."
 *   BOT_USERNAME="mtw_giveaway_bot"
 *   WEBAPP_URL="https://mfa-frontend.myinfra.dev/"
 *   ACTION_FEE_TON="0.03"
 *   DEST_ADDRESS="UQ..."
 *   TRANSFER_TON="0.01"
 */

const fs = require('node:fs');
const path = require('node:path');
const childProcess = require('node:child_process');

const tonMnemonic = require('tonweb-mnemonic');
const { TonClient, WalletContractV5R1 } = require('@ton/ton');
const {
  Address,
  beginCell,
  Cell,
  external,
  internal,
  SendMode,
  storeMessageRelaxed,
  toNano,
} = require('@ton/core');
const { sign } = require('@ton/crypto');

const MFA_API_BASE_URL = (process.env.MFA_API_BASE_URL || 'https://mfa-server.myinfra.dev').replace(/\/+$/, '');

const TONCENTER_ENDPOINT = process.env.TONCENTER_ENDPOINT || 'https://toncenter.mytonwallet.org/api/v2/jsonRPC';
const TONCENTER_API_KEY = process.env.TONCENTER_API_KEY;

const TELEGRAM_API_ID = process.env.TELEGRAM_API_ID;
const TELEGRAM_API_HASH = process.env.TELEGRAM_API_HASH;

const BOT_USERNAME = process.env.BOT_USERNAME || 'mtw_giveaway_bot';
const WEBAPP_URL = process.env.WEBAPP_URL || 'https://mfa-frontend.myinfra.dev/';

// Must be <= extension balance (it funds the internal wallet request).
const ACTION_FEE_TON = process.env.ACTION_FEE_TON || '0.03';
const TRANSFER_TON = process.env.TRANSFER_TON || '0.01';
const DEST_ADDRESS = process.env.DEST_ADDRESS || 'UQAXt7U0eHXLZhcngXzALAryEm_dtkTevqFfa2zc7UfcciR8';

const NETWORK_GLOBAL_ID = -239; // W5 mainnet chain id used by MyTonWallet

const SEED_FILE = path.join(process.cwd(), 'trash', 'TEST_WALLET_SEED.md');
const MTKRUTO_SIGN_SCRIPT = path.join(process.cwd(), 'trash', 'mtkruto', 'sign-payload.js');

const OpCode = {
  SEND_ACTIONS: 0xb15f2c8c,
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

  return {
    authDate: result.auth_date,
    signature: Buffer.from(result.signature, 'base64'),
  };
}

async function fetchJson(url, options) {
  const res = await fetch(url, {
    redirect: 'follow',
    ...options,
  });
  const text = await res.text();
  let body;
  try {
    body = text ? JSON.parse(text) : undefined;
  } catch {
    body = text;
  }
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} ${res.statusText}: ${typeof body === 'string' ? body : JSON.stringify(body)}`);
  }
  return body;
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
  console.log('Backend:', MFA_API_BASE_URL);
  console.log('Toncenter:', TONCENTER_ENDPOINT);

  const extensions = await openedWallet.getExtensionsArray();
  if (!extensions.length) {
    throw new Error('Wallet has no extensions installed. Install MFA Extension first.');
  }
  const extensionAddress = extensions[0];
  console.log('Extension:', formatAddress(extensionAddress));

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
  const payloadHashB64 = payload.hash().toString('base64');
  const seedSignature = Buffer.from(sign(payload.hash(), Buffer.from(keyPair.secretKey)));

  // 1) Create request on backend
  console.log('Creating request on backend ...');
  const create = await fetchJson(`${MFA_API_BASE_URL}/transaction`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      walletAddress: formatAddress(wallet.address),
      payload: payload.toBoc().toString('base64'),
      signature: seedSignature.toString('base64'),
    }),
  });
  const reqId = create.reqId;
  if (!reqId) throw new Error(`Backend did not return reqId: ${JSON.stringify(create)}`);
  console.log('reqId:', reqId);

  // 2) Fetch it back
  const stored = await fetchJson(`${MFA_API_BASE_URL}/transaction/${reqId}`);
  if (!stored.payload || !stored.signature) {
    throw new Error(`Backend returned invalid request: ${JSON.stringify(stored)}`);
  }

  // 3) Sign with Telegram + send external message to extension (simulate miniapp confirm)
  console.log('Signing payload via Telegram (MTKruto) ...');
  const tg = getTelegramSignedPayload(payloadHashB64);

  const message = prepareExternalMessage({
    payload: Cell.fromBase64(stored.payload),
    seedSignature: Buffer.from(stored.signature, 'base64'),
    telegramSignature: tg.signature,
    authDate: tg.authDate,
  });

  console.log('Sending external message to extension ...');
  await client.sendExternalMessage({ address: extensionAddress }, message);
  await waitForExtensionSeqno(client, extensionAddress, extensionSeqno + 1);

  const normalizedTxHash = getExternalMsgHashNormalized(external({ to: extensionAddress, body: message }));

  // 4) Confirm on backend
  console.log('Confirming request on backend ...');
  await fetchJson(`${MFA_API_BASE_URL}/transaction/${reqId}/confirm`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ txHash: normalizedTxHash }),
  });

  // 5) Verify backend marks it confirmed
  console.log('Waiting for backend confirmed flag ...');
  const deadline = Date.now() + 30_000;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const cur = await fetchJson(`${MFA_API_BASE_URL}/transaction/${reqId}`);
    if (cur.isConfirmed) break;
    if (Date.now() > deadline) throw new Error('Timed out waiting for backend confirmation');
    await sleep(500);
  }

  // Best-effort: wait for wallet execution / recipient balance update.
  await sleep(8_000);
  const destBalAfter = await client.getBalance(dest);

  console.log('Recipient balance before (nano):', destBalBefore.toString());
  console.log('Recipient balance after  (nano):', destBalAfter.toString());

  if (destBalAfter <= destBalBefore) {
    throw new Error('Recipient balance did not increase (transfer may have failed)');
  }

  console.log('OK: backend + telegram signature + extension flow works.');
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
