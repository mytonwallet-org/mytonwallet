/* eslint-disable no-console */
/**
 * Fix / (re)install MFA Extension for a specific W5 mainnet wallet and run an E2E backend flow test.
 *
 * What it does:
 * 1) Derives the wallet from `FUNDING_MNEMONIC` (W5 mainnet, networkGlobalId=-239)
 * 2) Ensures the expected MFA extension address exists in the wallet extensions list
 * 3) If the extension seqno is 0, sends the internal `op::install` from the wallet to complete the handshake
 *    (this disables secret-key auth on the wallet and "locks" it behind MFA)
 * 4) Runs an end-to-end MFA flow against `mfa-server` using a real Telegram signature via MTKruto
 *
 * Usage (mainnet):
 *   FUNDING_MNEMONIC="word1 ... word24" \\
 *   TELEGRAM_API_ID=... TELEGRAM_API_HASH=... \\
 *   node dev/mfa/fix_mfa_wallet_mainnet.js
 *
 * Optional env:
 *   TARGET_WALLET_ADDRESS="UQ..."          # defaults to `UQAXt7U0...` from the task
 *   TELEGRAM_ID="1368727604"
 *   MFA_EXTENSION_CODE_HASH="8cbd..."      # full code hash (hex), used for library-ref cell
 *   MFA_API_BASE_URL="https://mfa-server.myinfra.dev"
 *   TONCENTER_ENDPOINT="https://toncenter.mytonwallet.org/api/v2/jsonRPC"
 *   TONCENTER_API_KEY="..."
 *   BOT_USERNAME="mtw_giveaway_bot"
 *   WEBAPP_URL="https://mfa-frontend.myinfra.dev/"
 *   INSTALL_VALUE_TON="0.5"               # value sent from wallet to extension for install+funding
 *   ACTION_FEE_TON="0.03"                 # value attached to the wallet request (paid from extension balance)
 *   DEST_ADDRESS="UQ..."                  # recipient of the test transfer
 *   TRANSFER_TON="0.001"
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
  contractAddress,
  external,
  internal,
  SendMode,
  storeMessageRelaxed,
  toNano,
} = require('@ton/core');
const { sign } = require('@ton/crypto');

const FUNDING_MNEMONIC_RAW = process.env.FUNDING_MNEMONIC;
const TARGET_WALLET_ADDRESS = process.env.TARGET_WALLET_ADDRESS || 'UQAXt7U0eHXLZhcngXzALAryEm_dtkTevqFfa2zc7UfcciR8';

const TELEGRAM_API_ID = process.env.TELEGRAM_API_ID;
const TELEGRAM_API_HASH = process.env.TELEGRAM_API_HASH;

const TELEGRAM_ID = process.env.TELEGRAM_ID || '1368727604';
const BOT_USERNAME = process.env.BOT_USERNAME || 'mtw_giveaway_bot';
const WEBAPP_URL = process.env.WEBAPP_URL || 'https://mfa-frontend.myinfra.dev/';

const MFA_EXTENSION_CODE_HASH = process.env.MFA_EXTENSION_CODE_HASH
  || '8cbd6c85088b82aa06567d2cd2c180f201eeb270a74ec6223f569298e5448234';

const MFA_API_BASE_URL = (process.env.MFA_API_BASE_URL || 'https://mfa-server.myinfra.dev').replace(/\/+$/, '');

const TONCENTER_ENDPOINT = process.env.TONCENTER_ENDPOINT || 'https://toncenter.mytonwallet.org/api/v2/jsonRPC';
const TONCENTER_API_KEY = process.env.TONCENTER_API_KEY;

const INSTALL_VALUE_TON = process.env.INSTALL_VALUE_TON || '0.5';
const ACTION_FEE_TON = process.env.ACTION_FEE_TON || '0.03';
const TRANSFER_TON = process.env.TRANSFER_TON || '0.001';

// Default recipient: the local test wallet created by `dev/mfa/setup_test_wallet.js`
const DEST_ADDRESS = process.env.DEST_ADDRESS || 'UQC8Ynp78aAi5zEqa4o537qgHGnydd03InwdeuAARyBvDIKJ';

const NETWORK_GLOBAL_ID = -239; // W5 mainnet chain id used by MyTonWallet

const MTKRUTO_SIGN_SCRIPT = path.join(process.cwd(), 'trash', 'mtkruto', 'sign-payload.js');

const OpCode = {
  INSTALL: 0x43563174,
  SEND_ACTIONS: 0xb15f2c8c,
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
  const { stack, exit_code } = await client.runMethodWithError(extensionAddress, 'get_seqno');
  if (exit_code !== 0) {
    throw new Error(`get_seqno failed (exit_code=${exit_code}). Extension is likely broken or missing library.`);
  }
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

  if (result.telegram_id && String(result.telegram_id) !== String(TELEGRAM_ID)) {
    throw new Error(`Telegram session mismatch: expected id=${TELEGRAM_ID}, got id=${result.telegram_id}`);
  }

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
  if (!FUNDING_MNEMONIC_RAW) exitWithError('Missing env FUNDING_MNEMONIC (12/24 words).');

  const fundingMnemonic = FUNDING_MNEMONIC_RAW.trim().split(/\s+/).filter(Boolean);
  if (fundingMnemonic.length < 12) exitWithError('FUNDING_MNEMONIC looks invalid (expected 12/24 words).');

  const keyPair = await tonMnemonic.mnemonicToKeyPair(fundingMnemonic);

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
  console.log('Toncenter:', TONCENTER_ENDPOINT);
  console.log('Backend:', MFA_API_BASE_URL);
  console.log('TelegramId:', TELEGRAM_ID);

  const isSignatureAllowed = await openedWallet.getIsSecretKeyAuthEnabled();
  console.log('Wallet is_signature_allowed:', isSignatureAllowed);

  const code = getContractCodeLibraryRef();
  const data = mfaExtensionConfigToCell({
    telegramId: TELEGRAM_ID,
    walletAddress: wallet.address,
    seedPubkey: keyPair.publicKey,
  });
  const init = { code, data };
  const extensionAddress = contractAddress(0, init);

  console.log('Expected extension:', formatAddress(extensionAddress, { bounceable: true }));

  // Ensure extension is added to the wallet.
  const extensions = await openedWallet.getExtensionsArray();
  const hasExt = extensions.some((a) => a.toRawString() === extensionAddress.toRawString());
  if (!hasExt) {
    if (!isSignatureAllowed) {
      exitWithError('Wallet is locked (signature disabled) and does not have the expected extension in its dict. Only recovery can help.');
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
    console.log('Extension already present in wallet dict.');
  }

  // Ensure extension is deployed (state init).
  const deployed = await client.isContractDeployed(extensionAddress);
  console.log('Extension deployed:', deployed);

  if (!deployed) {
    if (!isSignatureAllowed) {
      exitWithError('Wallet is locked and extension is not deployed. Only recovery can help.');
    }

    const seqno = await openedWallet.getSeqno();
    console.log('Deploying extension with install body (seqno', seqno, ') ...');
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
  }

  // If it was deployed earlier but not installed (seqno=0), send the install message now.
  const extSeqnoBefore = await getExtensionSeqno(client, extensionAddress);
  console.log('Extension seqno:', extSeqnoBefore);

  if (extSeqnoBefore === 0) {
    if (!isSignatureAllowed) {
      exitWithError('Wallet is locked but extension seqno is 0 (unexpected). Aborting.');
    }

    const seqno = await openedWallet.getSeqno();
    console.log('Sending install message to extension (seqno', seqno, ') ...');
    await openedWallet.sendTransfer({
      authType: 'external',
      seqno,
      secretKey: keyPair.secretKey,
      messages: [
        internal({
          to: extensionAddress,
          value: toNano(INSTALL_VALUE_TON),
          bounce: false,
          body: beginCell().storeUint(OpCode.INSTALL, 32).endCell(),
        }),
      ],
    });
    await waitForWalletSeqnoBump(openedWallet, seqno);

    console.log('Waiting for wallet to disable secret-key auth (lock) ...');
    await waitForWalletSignatureAllowed(openedWallet, false);
  } else {
    console.log('Extension already installed (seqno > 0), skipping install.');
  }

  // --- E2E test via backend + Telegram signature ---
  console.log('Running E2E MFA flow test ...');

  const extensionSeqno = await getExtensionSeqno(client, extensionAddress);
  const walletSeqno = await openedWallet.getSeqno();
  console.log('Extension seqno (test):', extensionSeqno);
  console.log('Wallet seqno (test):', walletSeqno);

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

  // 2) Fetch it back (server-stored payload/signature)
  const stored = await fetchJson(`${MFA_API_BASE_URL}/transaction/${reqId}`);
  if (!stored.payload || !stored.signature) {
    throw new Error(`Backend returned invalid request: ${JSON.stringify(stored)}`);
  }

  // 3) Telegram signature + external message to extension
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

  await sleep(8_000);
  const destBalAfter = await client.getBalance(dest);

  console.log('Recipient:', formatAddress(dest));
  console.log('Recipient balance before (nano):', destBalBefore.toString());
  console.log('Recipient balance after  (nano):', destBalAfter.toString());

  if (destBalAfter <= destBalBefore) {
    throw new Error('Recipient balance did not increase (transfer may have failed)');
  }

  console.log('OK: MFA extension installed and E2E flow works.');
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

