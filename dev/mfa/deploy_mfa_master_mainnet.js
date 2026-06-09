/* eslint-disable no-console */
/**
 * Deploy (or reuse if already deployed) the MfaMaster contract on TON mainnet and
 * save its address to `trash/MFA_MASTER_ADDRESS.md`.
 *
 * Usage:
 *   node dev/mfa/deploy_mfa_master_mainnet.js
 *
 * Optional env:
 *   TONCENTER_ENDPOINT="https://toncenter.mytonwallet.org/api/v2/jsonRPC"
 *   TONCENTER_API_KEY="..."
 *   DEPLOY_VALUE_TON="0.1"
 */

const fs = require('node:fs');
const path = require('node:path');
const fsp = require('node:fs/promises');

const tonMnemonic = require('tonweb-mnemonic');
const { TonClient, WalletContractV5R1 } = require('@ton/ton');
const { Address, beginCell, Cell, contractAddress, internal, toNano } = require('@ton/core');

const TONCENTER_ENDPOINT = process.env.TONCENTER_ENDPOINT || 'https://toncenter.mytonwallet.org/api/v2/jsonRPC';
const TONCENTER_API_KEY = process.env.TONCENTER_API_KEY;

const DEPLOY_VALUE_TON = process.env.DEPLOY_VALUE_TON || '0.1';

const NETWORK_GLOBAL_ID = -239; // W5 mainnet chain id used by MyTonWallet

const SEED_FILE = path.join(process.cwd(), 'trash', 'TEST_WALLET_SEED.md');
const OUT_FILE = path.join(process.cwd(), 'trash', 'MFA_MASTER_ADDRESS.md');

const MASTER_COMPILED_JSON = path.resolve(__dirname, '../../..', 'mfa-extension', 'build', 'MfaMaster.compiled.json');

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

async function waitForDeploy(client, address, { timeoutMs = 120_000, pollMs = 2_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    if (await client.isContractDeployed(address)) return;
    if (Date.now() > deadline) throw new Error(`Timed out waiting for deploy: ${address.toRawString()}`);
    await sleep(pollMs);
  }
}

async function main() {
  if (!fs.existsSync(SEED_FILE)) throw new Error(`Seed file not found: ${SEED_FILE}`);
  if (!fs.existsSync(MASTER_COMPILED_JSON)) throw new Error(`Compiled MfaMaster not found: ${MASTER_COMPILED_JSON}`);

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

  const compiledRaw = fs.readFileSync(MASTER_COMPILED_JSON, 'utf8');
  const compiled = JSON.parse(compiledRaw);
  const code = Cell.fromBoc(Buffer.from(compiled.hex, 'hex'))[0];
  const data = beginCell().endCell();
  const init = { code, data };
  const masterAddress = contractAddress(0, init);

  console.log('Deployer wallet:', formatAddress(wallet.address));
  console.log('MfaMaster address:', formatAddress(masterAddress));
  console.log('MfaMaster code hash:', code.hash().toString('hex'));
  console.log('Toncenter:', TONCENTER_ENDPOINT);

  const isDeployed = await client.isContractDeployed(masterAddress);
  if (!isDeployed) {
    const seqno = await openedWallet.getSeqno();
    console.log('Deploying MfaMaster (seqno', seqno, ', value', DEPLOY_VALUE_TON, 'TON) ...');

    await openedWallet.sendTransfer({
      authType: 'external',
      seqno,
      secretKey: keyPair.secretKey,
      messages: [
        internal({
          to: masterAddress,
          value: toNano(DEPLOY_VALUE_TON),
          bounce: false,
          init,
          body: beginCell().endCell(),
        }),
      ],
    });

    await waitForWalletSeqnoBump(openedWallet, seqno);
    await waitForDeploy(client, masterAddress);
  } else {
    console.log('MfaMaster already deployed.');
  }

  // Sanity check: call get method expected by MyTonWallet client
  const dummy = beginCell().storeUint(0, 1).endCell();
  const { stack } = await client.runMethod(masterAddress, 'get_estimated_attached_value', [
    { type: 'cell', cell: dummy },
    { type: 'int', value: 1n },
    { type: 'int', value: 0n },
  ]);
  const estimate = stack.readBigNumber();
  console.log('get_estimated_attached_value(dummy) =', estimate.toString());

  const now = new Date().toISOString();
  const contents = [
    '# MFA Master (mainnet)',
    '',
    `Saved: ${now}`,
    `Address: ${formatAddress(masterAddress)}`,
    `Code hash: ${code.hash().toString('hex')}`,
    `Deployer wallet: ${formatAddress(wallet.address)}`,
    `Toncenter: ${TONCENTER_ENDPOINT}`,
    '',
    'Use in client env:',
    `MFA_MASTER_ADDRESS=${formatAddress(masterAddress)}`,
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

