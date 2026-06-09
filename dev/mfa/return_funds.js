/* eslint-disable no-console */
/**
 * Sends almost all funds from the TEST wallet (stored in trash/TEST_WALLET_SEED.md)
 * back to a destination address.
 *
 * Usage:
 *   DEST_ADDRESS="UQ..." node dev/mfa/return_funds.js
 *
 * Optional env:
 *   TONCENTER_ENDPOINT="https://toncenter.mytonwallet.org/api/v2/jsonRPC"
 *   TONCENTER_API_KEY="..."
 *   KEEP_TON="0.05"   # amount to keep for fees
 */

const fs = require('node:fs');
const path = require('node:path');

const tonMnemonic = require('tonweb-mnemonic');
const { TonClient, WalletContractV5R1 } = require('@ton/ton');
const { Address, internal, toNano } = require('@ton/core');

const TONCENTER_ENDPOINT = process.env.TONCENTER_ENDPOINT || 'https://toncenter.mytonwallet.org/api/v2/jsonRPC';
const TONCENTER_API_KEY = process.env.TONCENTER_API_KEY;

const NETWORK_GLOBAL_ID = -239; // W5 mainnet chain id used by MyTonWallet

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

async function waitSeqnoBump(opened, prev, { timeoutMs = 120_000, pollMs = 2_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const current = await opened.getSeqno();
    if (current > prev) return current;
    if (Date.now() > deadline) {
      throw new Error(`Timed out waiting for seqno bump (prev=${prev}, current=${current})`);
    }
    await sleep(pollMs);
  }
}

async function main() {
  const destRaw = process.env.DEST_ADDRESS;
  if (!destRaw) {
    throw new Error('Missing env DEST_ADDRESS (friendly TON address).');
  }

  if (!fs.existsSync(SEED_FILE)) {
    throw new Error(`Seed file not found: ${SEED_FILE}`);
  }

  const seedFileContents = fs.readFileSync(SEED_FILE, 'utf8');
  const mnemonic = parseMnemonicFromFile(seedFileContents);
  if (!mnemonic) {
    throw new Error(`Failed to parse mnemonic from: ${SEED_FILE}`);
  }

  const keepTon = process.env.KEEP_TON || '0.05';
  const keep = toNano(keepTon);

  const client = new TonClient({
    endpoint: TONCENTER_ENDPOINT,
    ...(TONCENTER_API_KEY ? { apiKey: TONCENTER_API_KEY } : {}),
  });

  const keyPair = await tonMnemonic.mnemonicToKeyPair(mnemonic);
  const wallet = WalletContractV5R1.create({
    publicKey: keyPair.publicKey,
    workchain: 0,
    walletId: { networkGlobalId: NETWORK_GLOBAL_ID },
  });

  const opened = client.open(wallet);

  const dest = Address.parseFriendly(destRaw).address;

  const [bal, seqno] = await Promise.all([
    client.getBalance(wallet.address),
    opened.getSeqno(),
  ]);

  console.log('From:', formatAddress(wallet.address));
  console.log('To:  ', formatAddress(dest));
  console.log('Balance (nano):', bal.toString());
  console.log('Seqno:', seqno);

  if (bal <= keep) {
    throw new Error(`Balance too low to send (balance=${bal.toString()}, keep=${keep.toString()})`);
  }

  const amount = bal - keep;
  console.log('Sending (nano):', amount.toString());

  await opened.sendTransfer({
    authType: 'external',
    seqno,
    secretKey: keyPair.secretKey,
    messages: [
      internal({
        to: dest,
        value: amount,
        bounce: false,
      }),
    ],
  });

  const newSeqno = await waitSeqnoBump(opened, seqno);
  console.log('Seqno after send:', newSeqno);

  const [newBal, destBal] = await Promise.all([
    client.getBalance(wallet.address),
    client.getBalance(dest),
  ]);

  console.log('New from balance (nano):', newBal.toString());
  console.log('Dest balance (nano):    ', destBal.toString());
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
