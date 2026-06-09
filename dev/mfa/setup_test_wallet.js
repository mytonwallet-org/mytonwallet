/* eslint-disable no-console */
/**
 * Creates (or reuses) a W5 mainnet wallet mnemonic in `trash/TEST_WALLET_SEED.md`,
 * then funds it from a provided funding mnemonic.
 *
 * Usage:
 *   FUNDING_MNEMONIC="word1 ... word24" node dev/mfa/setup_test_wallet.js
 *
 * Optional env:
 *   TONCENTER_ENDPOINT="https://toncenter.mytonwallet.org/api/v2/jsonRPC"
 *   TONCENTER_API_KEY="..."
 *   FUND_AMOUNT_TON="5"
 */

const fs = require('node:fs');
const path = require('node:path');

const tonMnemonic = require('tonweb-mnemonic');
const { TonClient, WalletContractV5R1 } = require('@ton/ton');
const { internal, toNano } = require('@ton/core');

const TONCENTER_ENDPOINT = process.env.TONCENTER_ENDPOINT || 'https://toncenter.mytonwallet.org/api/v2/jsonRPC';
const TONCENTER_API_KEY = process.env.TONCENTER_API_KEY;

const NETWORK_GLOBAL_ID = -239; // W5 mainnet chain id used by MyTonWallet

const FUND_AMOUNT_TON = process.env.FUND_AMOUNT_TON || '5';
const FUND_AMOUNT = toNano(FUND_AMOUNT_TON);
// When deploying the wallet with init, part of the value is spent on deployment fees,
// so the resulting balance may be slightly below the sent amount.
const EXPECTED_MIN_BALANCE = FUND_AMOUNT - toNano('0.1');

const SEED_FILE = path.join(process.cwd(), 'trash', 'TEST_WALLET_SEED.md');

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

async function waitForBalance(client, address, min, { timeoutMs = 120_000, pollMs = 3_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const bal = await client.getBalance(address);
    if (bal >= min) return bal;
    if (Date.now() > deadline) {
      throw new Error(`Timed out waiting for balance >= ${min.toString()} (current=${bal.toString()})`);
    }
    await sleep(pollMs);
  }
}

async function main() {
  const fundingMnemonicRaw = process.env.FUNDING_MNEMONIC;
  if (!fundingMnemonicRaw) {
    throw new Error('Missing env FUNDING_MNEMONIC (24 words).');
  }
  const fundingMnemonic = fundingMnemonicRaw.trim().split(/\s+/).filter(Boolean);
  if (fundingMnemonic.length < 12) {
    throw new Error('FUNDING_MNEMONIC looks invalid (expected 12/24 words).');
  }

  const client = new TonClient({
    endpoint: TONCENTER_ENDPOINT,
    ...(TONCENTER_API_KEY ? { apiKey: TONCENTER_API_KEY } : {}),
  });

  let testMnemonic;
  let seedFileContents;
  if (fs.existsSync(SEED_FILE)) {
    seedFileContents = fs.readFileSync(SEED_FILE, 'utf8');
    testMnemonic = parseMnemonicFromFile(seedFileContents);
    if (!testMnemonic) {
      throw new Error(`Failed to parse mnemonic from existing file: ${SEED_FILE}`);
    }
  }

  if (!testMnemonic) {
    testMnemonic = await tonMnemonic.generateMnemonic();
    fs.mkdirSync(path.dirname(SEED_FILE), { recursive: true });
  }

  const fundingKeyPair = await tonMnemonic.mnemonicToKeyPair(fundingMnemonic);
  const testKeyPair = await tonMnemonic.mnemonicToKeyPair(testMnemonic);

  const fundingWallet = WalletContractV5R1.create({
    publicKey: fundingKeyPair.publicKey,
    workchain: 0,
    walletId: { networkGlobalId: NETWORK_GLOBAL_ID },
  });
  const testWallet = WalletContractV5R1.create({
    publicKey: testKeyPair.publicKey,
    workchain: 0,
    walletId: { networkGlobalId: NETWORK_GLOBAL_ID },
  });

  if (!fs.existsSync(SEED_FILE)) {
    fs.writeFileSync(
      SEED_FILE,
      [
        '# TEST_WALLET_SEED (W5 mainnet)',
        '',
        `Generated: ${new Date().toISOString()}`,
        `Address: ${formatAddress(testWallet.address)}`,
        '',
        `Mnemonic: ${testMnemonic.join(' ')}`,
        '',
      ].join('\n'),
      'utf8',
    );
  } else if (seedFileContents && !/^\s*Address:\s*/im.test(seedFileContents)) {
    fs.appendFileSync(SEED_FILE, `Address: ${formatAddress(testWallet.address)}\n`, 'utf8');
  }

  const fundingOpened = client.open(fundingWallet);

  console.log('Funding wallet:', formatAddress(fundingWallet.address));
  console.log('Test wallet:   ', formatAddress(testWallet.address));

  const [fundingBal, testBal] = await Promise.all([
    client.getBalance(fundingWallet.address),
    client.getBalance(testWallet.address),
  ]);
  console.log('Funding balance:', fundingBal.toString());
  console.log('Test balance:   ', testBal.toString());

  if (testBal >= EXPECTED_MIN_BALANCE) {
    console.log(`Test wallet already funded (~${FUND_AMOUNT_TON} TON), skipping funding.`);
    return;
  }

  if (fundingBal < FUND_AMOUNT) {
    throw new Error('Funding wallet balance is too low for requested fund amount.');
  }

  const seqno = await fundingOpened.getSeqno();
  console.log('Funding seqno:', seqno);
  console.log(`Sending ${FUND_AMOUNT_TON} TON to test wallet (with init) ...`);

  await fundingOpened.sendTransfer({
    authType: 'external',
    seqno,
    secretKey: fundingKeyPair.secretKey,
    messages: [
      internal({
        to: testWallet.address,
        value: FUND_AMOUNT,
        bounce: false,
        init: testWallet.init,
      }),
    ],
  });

  const newBal = await waitForBalance(client, testWallet.address, EXPECTED_MIN_BALANCE);
  console.log('Test balance after funding:', newBal.toString());
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
