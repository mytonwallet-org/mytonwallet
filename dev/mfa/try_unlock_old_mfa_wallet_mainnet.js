/* eslint-disable no-console */
const tonMnemonic = require('tonweb-mnemonic');
const childProcess = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const { TonClient, WalletContractV5R1 } = require('@ton/ton');
const {
  Address,
  beginCell,
  external,
} = require('@ton/core');
const { sign } = require('@ton/crypto');

const FUNDING_MNEMONIC_RAW = process.env.FUNDING_MNEMONIC;
const TARGET_WALLET_ADDRESS = process.env.TARGET_WALLET_ADDRESS || 'UQC8Ynp78aAi5zEqa4o537qgHGnydd03InwdeuAARyBvDIKJ';
const TELEGRAM_API_ID = process.env.TELEGRAM_API_ID;
const TELEGRAM_API_HASH = process.env.TELEGRAM_API_HASH;
const BOT_USERNAME = process.env.BOT_USERNAME || 'mtw_giveaway_bot';
const WEBAPP_URL = process.env.WEBAPP_URL || 'https://mfa-frontend.myinfra.dev/';
const TONCENTER_ENDPOINT = process.env.TONCENTER_ENDPOINT || 'https://toncenter.mytonwallet.org/api/v2/jsonRPC';
const NETWORK_GLOBAL_ID = -239;
const MTKRUTO_SIGN_SCRIPT = path.join(process.cwd(), 'trash', 'mtkruto', 'sign-payload.js');

const OpCode = {
  REMOVE_EXTENSION: 0xaeb09887,
};

function exitWithError(message) {
  console.error(message);
  process.exit(1);
}

function formatAddress(address, { bounceable = false } = {}) {
  return address.toString({
    urlSafe: true,
    bounceable,
    testOnly: false,
  });
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

function parseSignedPayloadResult(result) {
  return {
    authDate: result.auth_date,
    signature: Buffer.from(result.signature, 'base64url'),
  };
}

function getTelegramSignedPayload(env) {
  if (!TELEGRAM_API_ID || !TELEGRAM_API_HASH) {
    throw new Error('Missing TELEGRAM_API_ID / TELEGRAM_API_HASH');
  }
  if (!fs.existsSync(MTKRUTO_SIGN_SCRIPT)) {
    throw new Error(`Missing MTKruto sign script: ${MTKRUTO_SIGN_SCRIPT}`);
  }

  return parseSignedPayloadResult(execNodeJson(MTKRUTO_SIGN_SCRIPT, {
    ...process.env,
    TELEGRAM_API_ID,
    TELEGRAM_API_HASH,
    BOT_USERNAME,
    WEBAPP_URL,
    ...env,
  }));
}

async function resolveOldExtension(client, walletAddress) {
  const { stack, exit_code } = await client.runMethodWithError(walletAddress, 'get_extensions');
  if (exit_code !== 0) return undefined;

  const cell = stack.readCellOpt();
  if (!cell) return undefined;

  const { Dictionary } = require('@ton/core');
  const dict = Dictionary.loadDirect(
    Dictionary.Keys.BigUint(256),
    Dictionary.Values.BigInt(1),
    cell,
  );
  const extensions = dict.keys().map((key) => Address.parseRaw(`0:${key.toString(16).padStart(64, '0')}`));

  for (const ext of extensions) {
    const oldCloudId = await client.runMethodWithError(ext, 'get_cloud_id');
    if (oldCloudId.exit_code === 0) {
      return {
        address: ext,
        cloudId: oldCloudId.stack.readBigNumber().toString(),
      };
    }
  }

  return undefined;
}

async function main() {
  if (!FUNDING_MNEMONIC_RAW) exitWithError('Missing env FUNDING_MNEMONIC.');

  const mnemonic = FUNDING_MNEMONIC_RAW.trim().split(/\s+/).filter(Boolean);
  const keyPair = await tonMnemonic.mnemonicToKeyPair(mnemonic);

  const client = new TonClient({ endpoint: TONCENTER_ENDPOINT });
  const wallet = WalletContractV5R1.create({
    publicKey: keyPair.publicKey,
    workchain: 0,
    walletId: { networkGlobalId: NETWORK_GLOBAL_ID },
  });

  const actual = wallet.address.toString({ urlSafe: true, bounceable: false, testOnly: false });
  const expected = Address.parse(TARGET_WALLET_ADDRESS).toString({ urlSafe: true, bounceable: false, testOnly: false });
  if (actual !== expected) {
    exitWithError(`Mnemonic wallet address mismatch. Expected ${expected}, got ${actual}.`);
  }

  const resolved = await resolveOldExtension(client, Address.parse(TARGET_WALLET_ADDRESS));
  if (!resolved) exitWithError('Failed to resolve old cloudId-based extension.');

  const extSeqno = Number((await client.runMethod(resolved.address, 'get_seqno')).stack.readBigNumber());
  const payload = prepareBodyWithoutSignature({
    opCode: OpCode.REMOVE_EXTENSION,
    seqno: extSeqno,
    payload: beginCell().endCell(),
  });
  const seedSignature = Buffer.from(sign(payload.hash(), Buffer.from(keyPair.secretKey)));

  console.log('Wallet:', actual);
  console.log('Extension:', formatAddress(resolved.address, { bounceable: true }));
  console.log('cloudId:', resolved.cloudId);
  console.log('Extension seqno:', extSeqno);

  const variants = [
    {
      name: 'payload_text_no_sha',
      signerEnv: {
        PAYLOAD_TEXT: resolved.cloudId,
        SIGN_SHA256: 'false',
        IS_PAYLOAD_BINARY: 'false',
        INIT_DATA_SIGN_FIELDS_JSON: JSON.stringify({ user: { id: true } }),
      },
    },
    {
      name: 'payload_text_sha',
      signerEnv: {
        PAYLOAD_TEXT: resolved.cloudId,
        SIGN_SHA256: 'true',
        IS_PAYLOAD_BINARY: 'false',
        INIT_DATA_SIGN_FIELDS_JSON: JSON.stringify({ user: { id: true } }),
      },
    },
    {
      name: 'payload_hash_chat_instance',
      signerEnv: {
        PAYLOAD_B64: payload.hash().toString('base64'),
        SIGN_SHA256: 'true',
        IS_PAYLOAD_BINARY: 'true',
        INIT_DATA_SIGN_FIELDS_JSON: JSON.stringify({ chat_instance: true }),
      },
    },
  ];

  for (const variant of variants) {
    console.log(`Trying variant: ${variant.name}`);
    try {
      const tg = getTelegramSignedPayload(variant.signerEnv);
      const body = prepareExternalMessage({
        payload,
        seedSignature,
        telegramSignature: tg.signature,
        authDate: tg.authDate,
      });

      await client.sendExternalMessage({ address: resolved.address, body });
      console.log(`Accepted by liteserver: ${variant.name}`);
      return;
    } catch (error) {
      console.log(`Rejected: ${variant.name}`);
      console.log(String(error?.response?.data?.error || error?.message || error));
    }
  }

  exitWithError('All old-plugin variants were rejected.');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
