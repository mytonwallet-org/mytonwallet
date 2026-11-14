import { getBase58Decoder } from '@solana/kit';
import {
  Address, beginCell, external, internal, storeMessage, storeMessageRelaxed, toNano,
} from '@ton/core';
import { Wallet } from 'ethers';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { after, before, beforeEach, describe, it } from 'node:test';

import { getDefaultUpstreams, startBroadcastGuard } from './broadcastGuard.mjs';

const CHAINS = ['ton', 'tron', 'solana', 'evm', 'utxo', 'backend'];
const TON_WALLET = Address.parse('0:' + '11'.repeat(32));
const TON_RECIPIENT = Address.parse('0:' + '22'.repeat(32));
const TON_JETTON_WALLET = Address.parse('0:' + '33'.repeat(32));
// Bitcoin genesis coinbase transaction
const BTC_GENESIS_HEX = '01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff4d04ffff001d0104455468652054696d65732030332f4a616e2f32303039204368616e63656c6c6f72206f6e206272696e6b206f66207365636f6e64206261696c6f757420666f722062616e6b73ffffffff0100f2052a01000000434104678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61deb649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5fac00000000';
const BTC_GENESIS_TXID = '4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b';
const UPSTREAM_CORS_ORIGIN = 'https://upstream.example';
const UPSTREAM_EXPOSED_HEADERS = 'X-Snapshot-At, Date';

// Every safety case also runs with the read cache, which must not change what reaches the upstream
for (const readCacheMs of [0, 2000]) describe(`broadcastGuard, read cache ${readCacheMs} ms`, () => {
  let upstream;
  let upstreamRequests;
  let guard;
  let ports;

  before(async () => {
    upstream = await startFakeUpstream((request) => upstreamRequests.push(request));
    const target = `http://127.0.0.1:${upstream.address().port}`;
    guard = await startBroadcastGuard({
      upstreams: CHAINS.map((chain) => ({ env: [chain], port: 0, target, chain })),
      controlPort: 0,
      readCacheMs,
    });
    ports = Object.fromEntries(CHAINS.map((chain, i) => [chain, guard.ports[i]]));
  });

  after(async () => {
    await guard.close();
    await new Promise((resolve) => upstream.close(resolve));
  });

  beforeEach(async () => {
    upstreamRequests = [];
    await fetch(`http://127.0.0.1:${guard.controlPort}/broadcasts`, { method: 'DELETE' });
  });

  it('forwards reads to the upstream', async () => {
    const response = await postJson(ports.ton, '/api/v2/jsonRPC', { id: 1, jsonrpc: '2.0', method: 'getAddressBalance' });

    assert.deepEqual(response, { echo: { id: 1, jsonrpc: '2.0', method: 'getAddressBalance' } });
    assert.equal(upstreamRequests.length, 1);
    assert.deepEqual(await (await fetch(`http://127.0.0.1:${guard.controlPort}/proxied`)).json(), { ton: 1 });
  });

  it('intercepts a TON send and decodes its recipient', async () => {
    const boc = buildTonExternalBoc();
    const response = await postJson(ports.ton, '/api/v2/jsonRPC', {
      id: 1, jsonrpc: '2.0', method: 'sendBocReturnHashNoError', params: { boc },
    });

    assert.equal(response.result['@type'], 'raw.extMessageInfo');
    assert.equal(upstreamRequests.length, 0);

    const recipient = TON_RECIPIENT.toString({ bounceable: false });
    const [broadcast] = await getBroadcasts(`?chain=ton&to=${recipient}`);
    assert.equal(broadcast.details.from, TON_WALLET.toRawString());
    assert.deepEqual(broadcast.details.messages, [{ to: TON_RECIPIENT.toRawString(), amount: toNano('1.5').toString() }]);
  });

  it('decodes the recipient and amount of a jetton transfer', async () => {
    const jettonTransfer = beginCell()
      .storeUint(0x0f8a7ea5, 32).storeUint(0, 64).storeCoins(20_000_000n)
      .storeAddress(TON_RECIPIENT).storeAddress(TON_WALLET).storeBit(false).storeCoins(1n).storeBit(false)
      .endCell();
    const boc = buildTonExternalBoc(internal({ to: TON_JETTON_WALLET, value: toNano('0.05'), body: jettonTransfer }));

    await postJson(ports.ton, '/api/v2/jsonRPC', { id: 1, jsonrpc: '2.0', method: 'sendBoc', params: { boc } });

    const [broadcast] = await getBroadcasts(`?chain=ton&to=${TON_RECIPIENT.toRawString()}`);
    assert.deepEqual(broadcast.toMessages.map((message) => message.jetton), [
      { to: TON_RECIPIENT.toRawString(), amount: '20000000' },
    ]);
  });

  it('intercepts a gasless TON send to the backend', async () => {
    const response = await postJson(ports.backend, '/diesel/w5/sendBoc', { boc: buildTonExternalBoc(), isAddition: true });

    assert.deepEqual(response, { result: 'ok' });
    assert.equal(upstreamRequests.length, 0);

    const [broadcast] = await getBroadcasts(`?chain=ton&to=${TON_RECIPIENT.toRawString()}`);
    assert.equal(broadcast.details.isGasless, true);
  });

  it('refuses gasless Solana and EVM sends relayed by the backend', async () => {
    const solana = await fetch(`http://127.0.0.1:${ports.backend}/diesel/solana/signAndSend`, {
      method: 'POST', body: JSON.stringify({ transaction: 'AA==' }),
    });
    const evm = await fetch(`http://127.0.0.1:${ports.backend}/diesel/evm/send`, {
      method: 'POST', body: JSON.stringify({ chain: 'ethereum', userOperation: {} }),
    });

    assert.deepEqual([solana.status, evm.status], [503, 503]);
    assert.equal(upstreamRequests.length, 0);
    assert.deepEqual((await getBroadcasts('')).map((broadcast) => [broadcast.chain, broadcast.details.isBlocked]), [
      ['solana', true], ['evm', true],
    ]);
  });

  it('refuses an EVM gasless send through the wallet API', async () => {
    const response = await postJson(ports.evm, '/v2', {
      id: 1, jsonrpc: '2.0', method: 'wallet_sendPreparedCalls', params: [{}],
    });

    assert.equal(response.error.code, -32000);
    assert.equal(upstreamRequests.length, 0);
    assert.equal((await getBroadcasts('?chain=evm'))[0].details.isBlocked, true);
  });

  it('answers an EVM batch with the send intercepted and the rest forwarded', async () => {
    const signer = Wallet.createRandom();
    const to = Wallet.createRandom().address;
    const raw = await signer.signTransaction({
      to, value: 10n, chainId: 1, nonce: 0, gasLimit: 21000, maxFeePerGas: 1n, maxPriorityFeePerGas: 1n,
    });

    const response = await postJson(ports.evm, '/ethereum/v2', [
      { id: 1, jsonrpc: '2.0', method: 'eth_chainId' },
      { id: 2, jsonrpc: '2.0', method: 'eth_sendRawTransaction', params: [raw] },
    ]);

    const [broadcast] = await getBroadcasts(`?chain=evm&to=${to}`);
    assert.deepEqual(response[0], { echo: { id: 1, jsonrpc: '2.0', method: 'eth_chainId' } });
    assert.equal(response[1].result, broadcast.hash);
    assert.equal(broadcast.details.from, signer.address);
    assert.equal(upstreamRequests[0].body.length, 1);
  });

  it('retries the rest of a batch with a send when the upstream rate limits it', async () => {
    const to = Wallet.createRandom().address;
    const raw = await Wallet.createRandom().signTransaction({
      to, value: 10n, chainId: 1, nonce: 0, gasLimit: 21000, maxFeePerGas: 1n, maxPriorityFeePerGas: 1n,
    });

    const response = await postJson(ports.evm, '/ethereum/v2?limited=1&times=1', [
      { id: 1, jsonrpc: '2.0', method: 'eth_chainId' },
      { id: 2, jsonrpc: '2.0', method: 'eth_sendRawTransaction', params: [raw] },
    ]);

    assert.deepEqual(response[0], { echo: { id: 1, jsonrpc: '2.0', method: 'eth_chainId' } });
    assert.equal(upstreamRequests.length, 2);
  });

  it('returns the first signature of a Solana transaction', async () => {
    const signature = randomBytes(64);
    const wire = Buffer.concat([Buffer.from([1]), signature, randomBytes(100)]);

    const response = await postJson(ports.solana, '/', {
      id: 1, jsonrpc: '2.0', method: 'sendTransaction', params: [wire.toString('base64'), { encoding: 'base64' }],
    });

    assert.equal(response.result, getBase58Decoder().decode(signature));
    assert.equal(upstreamRequests.length, 0);
  });

  it('intercepts a TRON broadcast', async () => {
    const transaction = {
      txID: 'ab'.repeat(32),
      raw_data: { contract: [{ type: 'TransferContract', parameter: { value: { to_address: '41aa', amount: 5 } } }] },
    };

    const response = await postJson(ports.tron, '/wallet/broadcasttransaction', transaction);

    assert.deepEqual(response, { result: true, txid: transaction.txID });
    assert.equal((await getBroadcasts('?chain=tron&to=41aa')).length, 1);
    assert.equal(upstreamRequests.length, 0);
  });

  it('refuses a TRON hex broadcast instead of forwarding it', async () => {
    const response = await fetch(`http://127.0.0.1:${ports.tron}/wallet/broadcasthex`, {
      method: 'POST', body: JSON.stringify({ transaction: 'ab' }),
    });

    assert.equal(response.status, 503);
    assert.equal(upstreamRequests.length, 0);
  });

  it('intercepts a UTXO broadcast and returns its txid', async () => {
    const response = await fetch(`http://127.0.0.1:${ports.utxo}/bitcoin/api/v2/sendtx/`, {
      method: 'POST', body: BTC_GENESIS_HEX,
    }).then((r) => r.json());

    assert.deepEqual(response, { result: BTC_GENESIS_TXID });
    assert.equal(upstreamRequests.length, 0);
  });

  it('refuses backend POSTs that are not known reads, such as signed swap and perps actions', async () => {
    const statuses = [];
    for (const target of ['/swap/execute', '/perps/position/execute', '/perps/position/close/execute', '/new/relay']) {
      statuses.push((await fetch(`http://127.0.0.1:${ports.backend}${target}`, { method: 'POST', body: '{}' })).status);
    }
    const read = await postJson(ports.backend, '/swap/estimate', { from: 'TON' });
    await postJson(ports.backend, '/assets?langCode=en', { assets: ['TON'] });
    statuses.push((await fetch(`http://127.0.0.1:${ports.backend}/diesel/sendBoc?boc=x`)).status);

    assert.deepEqual(statuses, [503, 503, 503, 503, 503]);
    assert.deepEqual(read, { echo: { from: 'TON' } });
    assert.deepEqual(upstreamRequests.map((request) => request.path), ['/swap/estimate', '/assets?langCode=en']);
    assert.equal((await getBroadcasts('?chain=backend')).length, 5);
  });

  it('intercepts TON REST sends with a trailing slash and refuses other send forms', async () => {
    await postJson(ports.ton, '/api/v3/message/', { boc: buildTonExternalBoc() });
    const tonGet = await fetch(`http://127.0.0.1:${ports.ton}/api/v2/sendBoc?boc=x`);
    const utxoGet = await fetch(`http://127.0.0.1:${ports.utxo}/bitcoin/api/v2/sendtx/${BTC_GENESIS_HEX}`);

    assert.deepEqual([tonGet.status, utxoGet.status], [503, 503]);
    assert.equal(upstreamRequests.length, 0);
    assert.equal((await getBroadcasts(`?chain=ton&to=${TON_RECIPIENT.toRawString()}`)).length, 1);
  });

  it('finds a send behind a malformed batch member and refuses unknown send methods', async () => {
    const boc = buildTonExternalBoc();
    const ton = await postJson(ports.ton, '/api/v2/jsonRPC', [
      { id: 0 }, { id: 1, jsonrpc: '2.0', method: 'sendBoc', params: { boc } },
    ]);
    const evm = await postJson(ports.evm, '/ethereum/v2', { id: 1, jsonrpc: '2.0', method: 'eth_sendBundle', params: [] });

    assert.equal(ton[1].result['@type'], 'raw.extMessageInfo');
    assert.equal(evm.error.code, -32000);
    assert.equal(upstreamRequests.every((request) => !JSON.stringify(request.body).includes('send')), true);
  });

  it('answers CORS for a browser app on another origin itself', async () => {
    const origin = 'http://127.0.0.1:4180';
    const preflight = await fetch(`http://127.0.0.1:${ports.ton}/api/v3/walletStates`, {
      method: 'OPTIONS',
      headers: { origin, 'access-control-request-method': 'GET', 'access-control-request-headers': 'x-app-env' },
    });
    const read = await fetch(`http://127.0.0.1:${ports.ton}/api/v3/walletStates`, { headers: { origin } });

    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get('access-control-allow-origin'), origin);
    assert.equal(preflight.headers.get('access-control-allow-headers'), 'x-app-env');
    assert.equal(read.headers.get('access-control-allow-origin'), origin);
    assert.equal(read.headers.get('access-control-expose-headers'), UPSTREAM_EXPOSED_HEADERS);
    assert.equal(upstreamRequests.length, 1);
  });

  it('leaves a page outside the local machine to the upstream CORS policy', async () => {
    const origin = 'https://example.com';
    const preflight = await fetch(`http://127.0.0.1:${ports.ton}/api/v3/walletStates`, {
      method: 'OPTIONS',
      headers: { origin, 'access-control-request-method': 'POST' },
    });
    const read = await fetch(`http://127.0.0.1:${ports.ton}/api/v3/walletStates`, { headers: { origin } });

    assert.equal(preflight.headers.get('access-control-allow-origin'), UPSTREAM_CORS_ORIGIN);
    assert.equal(read.headers.get('access-control-allow-origin'), UPSTREAM_CORS_ORIGIN);
    assert.equal(read.headers.get('access-control-allow-credentials'), null);
    assert.equal(upstreamRequests.length, 2);
  });

  it('waits out a rate limit given as an HTTP date', async () => {
    const startedAt = Date.now();
    const read = await fetch(`http://127.0.0.1:${ports.ton}/rate-limited-until?times=1`);

    assert.equal(read.status, 200);
    assert.ok(Date.now() - startedAt >= 1500);
  });

  it('does not resend a backend POST the upstream rate limits', async () => {
    const response = await fetch(`http://127.0.0.1:${ports.backend}/assets?limited=1&times=1`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{"ids":[]}',
    });

    assert.equal(response.status, 429);
    assert.equal(upstreamRequests.length, 1);
  });

  it('retries a read the upstream rate limits, then passes the limit on', async () => {
    const recovered = await fetch(`http://127.0.0.1:${ports.ton}/rate-limited?times=2`);
    const stuck = await fetch(`http://127.0.0.1:${ports.ton}/rate-limited?times=9`);

    assert.equal(recovered.status, 200);
    assert.equal(stuck.status, 429);
    assert.equal(upstreamRequests.length, 3 + 4);
  });

  it('does not pass an upstream redirect to another host on to the app', async () => {
    const statuses = [];
    for (const location of ['https://example.com/x', 'https:example.com/x', '/\\example.com/x', '//example.com/x']) {
      const response = await fetch(`http://127.0.0.1:${ports.ton}/redirect?to=${encodeURIComponent(location)}`, {
        redirect: 'manual',
      });
      statuses.push(response.status);
    }

    assert.deepEqual(statuses, [502, 502, 502, 502]);
  });

  it('does not follow a redirect with the forwarded part of a batch', async () => {
    const raw = await Wallet.createRandom().signTransaction({
      to: Wallet.createRandom().address, value: 1n, chainId: 1, nonce: 0, gasLimit: 21000, maxFeePerGas: 1n, maxPriorityFeePerGas: 1n,
    });
    // The fake upstream records every request, so a followed redirect would show up as a second one
    const elsewhere = `http://127.0.0.1:${upstream.address().port}/elsewhere`;
    const response = await fetch(`http://127.0.0.1:${ports.evm}/redirect?to=${encodeURIComponent(elsewhere)}`, {
      method: 'POST',
      body: JSON.stringify([
        { id: 1, jsonrpc: '2.0', method: 'eth_chainId' },
        { id: 2, jsonrpc: '2.0', method: 'eth_sendRawTransaction', params: [raw] },
      ]),
    });

    assert.equal(response.status, 502);
    assert.deepEqual(upstreamRequests.map((request) => request.path.split('?')[0]), ['/redirect']);
  });

  it('logs the reads an upstream refuses, alone or in a batch with a send, without their query', async () => {
    const raw = await Wallet.createRandom().signTransaction({
      to: Wallet.createRandom().address, value: 1n, chainId: 1, nonce: 0, gasLimit: 21000, maxFeePerGas: 1n, maxPriorityFeePerGas: 1n,
    });
    const errors = [];
    const consoleError = console.error;
    console.error = (line) => errors.push(String(line));
    try {
      await fetch(`http://127.0.0.1:${ports.ton}/refuse/read?key=secret`, { method: 'POST', body: '{}' });
      await fetch(`http://127.0.0.1:${ports.evm}/refuse/batch?key=secret`, {
        method: 'POST',
        body: JSON.stringify([
          { id: 1, jsonrpc: '2.0', method: 'eth_chainId' },
          { id: 2, jsonrpc: '2.0', method: 'eth_sendRawTransaction', params: [raw] },
        ]),
      });
    } finally {
      console.error = consoleError;
    }

    assert.deepEqual(errors.filter((line) => line.includes('HTTP')), [
      'ton POST /refuse/read: HTTP 503',
      'evm POST /refuse/batch: HTTP 503',
    ]);
  });

  it('matches sends on the path servers see, whatever its spelling', async () => {
    const statuses = [];
    const targets = [
      [ports.ton, '/api/v2/send%42oc'], [ports.ton, '/api/v3//message'], [ports.ton, '/api/v3/message;a=1'],
      [ports.ton, '/api/v2/sendQuery'], [ports.tron, '/walletsolidity/broadcasttransaction'],
      [ports.utxo, '/api/v1/sendtx/ab'], [ports.backend, '/staking/..%2fswap/execute'],
    ];
    for (const [port, target] of targets) {
      statuses.push((await fetch(`http://127.0.0.1:${port}${target}`, { method: 'POST', body: '{}' })).status);
    }

    assert.equal(statuses.every((status) => status >= 500), true, String(statuses));
    assert.equal(upstreamRequests.length, 0);
  });

  it('refuses RPC bodies it cannot read for sends but forwards a read with a method param', async () => {
    const boc = buildTonExternalBoc();
    const send = JSON.stringify({ id: 1, jsonrpc: '2.0', method: 'sendBoc', params: { boc } });
    const statuses = [];
    for (const [method, body] of [
      ['PUT', send], ['POST', `\uFEFF${send}`], ['POST', `[[${send}]]`],
      ['POST', `{"method":"sendBoc","params":{"boc":"${boc}"},"method":"getMasterchainInfo"}`],
    ]) {
      statuses.push((await fetch(`http://127.0.0.1:${ports.ton}/api/v2/jsonRPC`, { method, body })).status);
    }
    const read = await postJson(ports.ton, '/api/v2/jsonRPC', {
      id: 1, jsonrpc: '2.0', method: 'runGetMethod', params: { address: 'x', method: 'seqno', stack: [] },
    });

    assert.deepEqual(statuses, [200, 200, 503, 503]);
    assert.equal((await getBroadcasts('?chain=ton')).filter((broadcast) => broadcast.hash).length, 2);
    assert.equal(read.echo.method, 'runGetMethod');
    assert.deepEqual(upstreamRequests.map((request) => request.body.method), ['runGetMethod']);
  });

  it('keeps a `//host` request target on the guarded upstream', async () => {
    await fetch(`http://127.0.0.1:${ports.ton}/api/v2/jsonRPC`, { method: 'GET' });
    const response = await new Promise((resolve, reject) => {
      http.get({ host: '127.0.0.1', port: ports.ton, path: '//127.0.0.1:1/api/v3/actions' }, resolve).on('error', reject);
    });
    response.resume();

    assert.equal(response.statusCode, 200);
    assert.equal(upstreamRequests.at(-1).path, '//127.0.0.1:1/api/v3/actions');
  });

  async function getBroadcasts(query) {
    return (await fetch(`http://127.0.0.1:${guard.controlPort}/broadcasts${query}`)).json();
  }
});

describe('broadcastGuard fixtures', () => {
  let upstream;
  let upstreamRequests;
  let guard;
  let recordDir;
  let fixturesDir;

  before(async () => {
    upstream = await startFakeUpstream((request) => upstreamRequests.push(request));
    recordDir = fs.mkdtempSync(path.join(os.tmpdir(), 'guard-record-'));
    fixturesDir = fs.mkdtempSync(path.join(os.tmpdir(), 'guard-fixtures-'));
    guard = await startBroadcastGuard({
      upstreams: [{ env: ['ton'], port: 0, target: `http://127.0.0.1:${upstream.address().port}`, chain: 'ton' }],
      controlPort: 0,
      fixturesDir,
      recordDir,
      recordPaths: '^/api/v3/actions',
    });
  });

  after(async () => {
    await guard.close();
    await new Promise((resolve) => upstream.close(resolve));
    fs.rmSync(recordDir, { recursive: true });
    fs.rmSync(fixturesDir, { recursive: true });
  });

  beforeEach(async () => {
    upstreamRequests = [];
    await fetch(`http://127.0.0.1:${guard.controlPort}/fixtures`, { method: 'DELETE' });
  });

  it('answers a matching read with the latest fixture instead of the upstream', async () => {
    await setFixtures('POST', [
      { chain: 'ton', path: '^/api/v3/actions', body: { actions: ['shared'] } },
      { chain: 'ton', path: '^/api/v3/actions\\?.*limit=1', body: { actions: ['pending'] } },
    ]);

    const response = await fetch(`http://127.0.0.1:${guard.ports[0]}/api/v3/actions?account=x&limit=1`);

    assert.deepEqual(await response.json(), { actions: ['pending'] });
    assert.equal(upstreamRequests.length, 0);
  });

  it('forwards reads no fixture matches and records the answers to the recorded paths', async () => {
    await setFixtures('PUT', [{ chain: 'ton', path: '^/api/v3/traces', body: {} }]);

    await fetch(`http://127.0.0.1:${guard.ports[0]}/api/v3/actions?account=x`);
    await fetch(`http://127.0.0.1:${guard.ports[0]}/api/v3/walletStates?address=x`);

    assert.equal(upstreamRequests.length, 2);
    const recorded = fs.readdirSync(recordDir).map((name) => JSON.parse(fs.readFileSync(path.join(recordDir, name))));
    assert.deepEqual(recorded.map(({ chain, method, path: target }) => [chain, method, target]), [
      ['ton', 'GET', '/api/v3/actions?account=x'],
    ]);
  });

  it('loads fixtures by name from the fixtures folder', async () => {
    fs.writeFileSync(path.join(fixturesDir, 'pending.json'), JSON.stringify([
      { chain: 'ton', path: '^/api/v3/actions', body: { actions: ['from file'] } },
    ]));

    const escaping = await fetch(`http://127.0.0.1:${guard.controlPort}/fixtures?load=../secret`, { method: 'POST' });
    await fetch(`http://127.0.0.1:${guard.controlPort}/fixtures?load=pending`, { method: 'POST' });
    const response = await fetch(`http://127.0.0.1:${guard.ports[0]}/api/v3/actions?account=x`);

    assert.equal(escaping.status, 400);
    assert.deepEqual(await response.json(), { actions: ['from file'] });
  });

  it('does not let a fixture on a JSON-RPC path answer a send', async () => {
    await setFixtures('POST', [{ chain: 'ton', method: 'POST', path: '^/api/v2/jsonRPC', body: { result: 'fixture' } }]);

    const response = await fetch(`http://127.0.0.1:${guard.ports[0]}/api/v2/jsonRPC`, {
      method: 'POST', body: JSON.stringify({ id: 1, jsonrpc: '2.0', method: 'sendBoc', params: { boc: buildTonExternalBoc() } }),
    });

    assert.equal((await response.json()).result['@type'], 'raw.extMessageInfo');
    assert.equal(upstreamRequests.length, 0);
  });

  it('rejects a fixture without a path', async () => {
    const response = await fetch(`http://127.0.0.1:${guard.controlPort}/fixtures`, {
      method: 'POST', body: JSON.stringify({ chain: 'ton', body: {} }),
    });

    assert.equal(response.status, 400);
  });

  async function setFixtures(method, fixtures) {
    await fetch(`http://127.0.0.1:${guard.controlPort}/fixtures`, { method, body: JSON.stringify(fixtures) });
  }
});

function buildTonExternalBoc(message = internal({ to: TON_RECIPIENT, value: toNano('1.5'), bounce: false })) {
  const transfer = beginCell().store(storeMessageRelaxed(message)).endCell();
  const body = beginCell().storeBuffer(randomBytes(64)).storeUint(0, 32).storeRef(transfer).endCell();

  return beginCell()
    .store(storeMessage(external({ to: TON_WALLET, body })))
    .endCell()
    .toBoc()
    .toString('base64');
}

async function postJson(port, path, data) {
  const response = await fetch(`http://127.0.0.1:${port}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(data),
  });

  return response.json();
}

function startFakeUpstream(onRequest, shouldRefuse = () => false) {
  const rateLimitedCounts = new Map();
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const chunks = [];
      req.on('data', (chunk) => chunks.push(chunk));
      req.on('end', () => {
        if (req.url.startsWith('/redirect')) {
          onRequest({ path: req.url });
          res.writeHead(307, { location: new URL(req.url, 'http://x').searchParams.get('to') });
          res.end();
          return;
        }
        const body = JSON.parse(Buffer.concat(chunks).toString() || 'null');
        onRequest({ path: req.url, body });
        const rateLimitedCount = (rateLimitedCounts.get(req.url) ?? 0) + 1;
        rateLimitedCounts.set(req.url, rateLimitedCount);
        const limitedTimes = Number(new URL(req.url, 'http://x').searchParams.get('times'));
        if ((req.url.startsWith('/rate-limited') || req.url.includes('limited=1')) && rateLimitedCount <= limitedTimes) {
          const retryAfter = req.url.startsWith('/rate-limited-until') ? new Date(Date.now() + 3000).toUTCString() : '0';
          res.writeHead(429, { 'retry-after': retryAfter });
          res.end();
          return;
        }
        const echo = Array.isArray(body) ? body.map((call) => ({ echo: call })) : { echo: body };
        const answer = req.url.startsWith('/rpc-error') ? { id: body?.id, jsonrpc: '2.0', error: { code: 429 } } : echo;
        const status = req.url.startsWith('/refuse') || shouldRefuse() ? 503 : 200;
        const snapshotHeaders = req.url.includes('/snapshot') ? { 'x-snapshot-at': String(Date.now()) } : {};
        setTimeout(() => {
          res.writeHead(status, {
            'content-type': 'application/json',
            'access-control-allow-origin': UPSTREAM_CORS_ORIGIN,
            'access-control-expose-headers': UPSTREAM_EXPOSED_HEADERS,
            ...snapshotHeaders,
          });
          res.end(req.url.startsWith('/html') ? '<html>Bad gateway</html>' : JSON.stringify(answer));
        }, req.url.startsWith('/slow') ? 100 : 0);
      });
    });
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

describe('broadcastGuard read cache', () => {
  const READ_CACHE_MS = 300;
  let upstream;
  let upstreamRequests;
  let guard;
  let ports;
  let refusalsLeft;

  before(async () => {
    upstream = await startFakeUpstream((request) => upstreamRequests.push(request), () => {
      refusalsLeft--;
      return refusalsLeft >= 0;
    });
    const target = `http://127.0.0.1:${upstream.address().port}`;
    guard = await startBroadcastGuard({
      upstreams: ['ton', 'evm', 'backend', 'evm'].map((chain) => ({ env: [chain], port: 0, target, chain })),
      controlPort: 0,
      readCacheMs: READ_CACHE_MS,
    });
    ports = { ton: guard.ports[0], evm: guard.ports[1], backend: guard.ports[2], otherEvm: guard.ports[3] };
  });

  after(async () => {
    await guard.close();
    await new Promise((resolve) => upstream.close(resolve));
  });

  beforeEach(async () => {
    upstreamRequests = [];
    refusalsLeft = 0;
    await new Promise((resolve) => { setTimeout(resolve, READ_CACHE_MS); });
  });

  it('lets a request that waited for a failed read ask the upstream itself', async () => {
    refusalsLeft = 1;
    const get = () => fetch(`http://127.0.0.1:${ports.ton}/slow/api/v3/account?address=a`);

    const statuses = (await Promise.all([get(), get()])).map((response) => response.status);

    assert.deepEqual(statuses.sort(), [200, 503]);
    assert.equal(upstreamRequests.length, 2);
  });

  it('caches the success a request gets after waiting for a failed read', async () => {
    refusalsLeft = 1;
    const get = () => fetch(`http://127.0.0.1:${ports.ton}/slow/api/v3/account?address=a`);

    await Promise.all([get(), get()]);
    const later = await get();

    assert.equal(later.status, 200);
    assert.equal(upstreamRequests.length, 2);
  });

  it('sends the retries of requests that waited for a failed read upstream once', async () => {
    refusalsLeft = 1;
    const get = () => fetch(`http://127.0.0.1:${ports.ton}/slow/api/v3/account?address=a`);

    const statuses = (await Promise.all([get(), get(), get()])).map((response) => response.status);

    assert.deepEqual(statuses.sort(), [200, 200, 503]);
    assert.equal(upstreamRequests.length, 2);
  });

  it('retries a failed read once for all requests that waited for it and keeps no failed answer', async () => {
    refusalsLeft = 3;
    const get = () => fetch(`http://127.0.0.1:${ports.ton}/slow/api/v3/account?address=a`);

    const statuses = (await Promise.all([get(), get(), get()])).map((response) => response.status);
    const later = await get();

    assert.deepEqual(statuses, [503, 503, 503]);
    assert.equal(later.status, 503);
    assert.equal(upstreamRequests.length, 3);
  });

  it('answers an identical read from the cache until it expires', async () => {
    const get = () => fetch(`http://127.0.0.1:${ports.ton}/api/v3/account?address=a`).then((response) => response.json());

    await get();
    await get();
    assert.equal(upstreamRequests.length, 1);

    await new Promise((resolve) => { setTimeout(resolve, READ_CACHE_MS + 50); });
    await get();
    assert.equal(upstreamRequests.length, 2);
  });

  it('does not cache a successful answer that is not JSON', async () => {
    const get = () => fetch(`http://127.0.0.1:${ports.ton}/html/api/v3/account?address=a`).then((response) => response.text());

    await get();
    await get();
    assert.equal(upstreamRequests.length, 2);
  });

  it('ignores the toncenter cache buster in the key and forwards it unchanged', async () => {
    await fetch(`http://127.0.0.1:${ports.ton}/api/v3/account?address=a&_=1`);
    await fetch(`http://127.0.0.1:${ports.ton}/api/v3/account?address=a&_=2`);

    assert.deepEqual(upstreamRequests.map(({ path }) => path), ['/api/v3/account?address=a&_=1']);
  });

  it('keeps answers of upstreams with the same target apart', async () => {
    const call = { id: 1, jsonrpc: '2.0', method: 'eth_getBalance', params: [] };
    await postJson(ports.evm, '/v2', call);
    await postJson(ports.otherEvm, '/v2', call);

    assert.equal(upstreamRequests.length, 2);
  });

  it('sends concurrent identical JSON-RPC reads upstream once and keeps other bodies and paths apart', async () => {
    const call = { id: 1, jsonrpc: '2.0', method: 'getAddressBalance', params: { address: 'a' } };
    const responses = await Promise.all([
      postJson(ports.ton, '/slow/api/v2/jsonRPC', call),
      postJson(ports.ton, '/slow/api/v2/jsonRPC', call),
      postJson(ports.ton, '/slow/api/v2/jsonRPC', { ...call, params: { address: 'b' } }),
      postJson(ports.ton, '/slow/api/v3/jsonRPC', call),
    ]);

    assert.deepEqual(responses[0], { echo: call });
    assert.deepEqual(responses[1], { echo: call });
    assert.equal(upstreamRequests.length, 3);
  });

  it('does not cache errors, rate limits inside JSON-RPC answers, simulations or backend requests', async () => {
    const read = { id: 1, jsonrpc: '2.0', method: 'eth_getBalance', params: [] };
    const simulation = { id: 1, jsonrpc: '2.0', method: 'simulateTransaction', params: [] };
    for (let i = 0; i < 2; i++) {
      await fetch(`http://127.0.0.1:${ports.ton}/refuse/api/v3/account`);
      await postJson(ports.evm, '/rpc-error', read);
      await postJson(ports.evm, '/v2', simulation);
      await postJson(ports.backend, '/swap/estimate', { from: 'ton' });
      await fetch(`http://127.0.0.1:${ports.backend}/utils/get-config`);
    }

    assert.equal(upstreamRequests.length, 10);
  });

  it('does not cache fee estimates', async () => {
    for (let i = 0; i < 2; i++) {
      await postJson(ports.evm, '/v2', { id: 1, jsonrpc: '2.0', method: 'eth_estimateGas', params: [] });
      await postJson(ports.ton, '/api/v2/jsonRPC', { id: 1, jsonrpc: '2.0', method: 'estimateFee', params: {} });
      await fetch(`http://127.0.0.1:${ports.ton}/api/v2/estimatefee/1`);
    }

    assert.equal(upstreamRequests.length, 6);
  });

  it('shares an answer stamped with its snapshot time only with requests in flight', async () => {
    const get = () => fetch(`http://127.0.0.1:${ports.evm}/slow/snapshot/positions`);

    const statuses = (await Promise.all([get(), get()])).map((response) => response.status);
    assert.deepEqual(statuses, [200, 200]);
    assert.equal(upstreamRequests.length, 1);

    await get();
    assert.equal(upstreamRequests.length, 2);
  });

  it('does not cache a batch with a send, which is intercepted every time', async () => {
    const signer = Wallet.createRandom();
    const raw = await signer.signTransaction({
      to: signer.address, value: 1n, chainId: 1, nonce: 0, gasLimit: 21000, maxFeePerGas: 1n, maxPriorityFeePerGas: 1n,
    });
    const batch = [
      { id: 1, jsonrpc: '2.0', method: 'eth_chainId' },
      { id: 2, jsonrpc: '2.0', method: 'eth_sendRawTransaction', params: [raw] },
    ];

    await postJson(ports.evm, '/v2', batch);
    await postJson(ports.evm, '/v2', batch);

    assert.equal(upstreamRequests.length, 2);
    assert.equal(guard.broadcasts.filter((broadcast) => broadcast.chain === 'evm').length, 2);
  });

  it('retries a rate-limited read once for all requests waiting for it', async () => {
    const get = () => fetch(`http://127.0.0.1:${ports.ton}/rate-limited?times=2&shared=1`);

    const statuses = (await Promise.all([get(), get(), get()])).map((response) => response.status);

    assert.deepEqual(statuses, [200, 200, 200]);
    assert.equal(upstreamRequests.length, 3);
  });

  it('gives a cached answer the CORS headers of the local app that asked', async () => {
    const origin = 'http://localhost:4180';
    const get = () => fetch(`http://127.0.0.1:${ports.ton}/api/v3/walletStates?cors=1`, { headers: { origin } });

    const fetched = await get();
    const cached = await get();

    assert.equal(upstreamRequests.length, 1);
    assert.equal(fetched.headers.get('access-control-allow-origin'), origin);
    assert.equal(cached.headers.get('access-control-allow-origin'), origin);
    assert.equal(cached.headers.get('access-control-expose-headers'), UPSTREAM_EXPOSED_HEADERS);
  });
});

describe('broadcastGuard upstreams', () => {
  const getBackendTarget = (env) => getDefaultUpstreams(env).find(({ chain }) => chain === 'backend').target;

  it('forwards the backend to beta unless another one is set', () => {
    assert.equal(getBackendTarget({}), 'https://api-beta.mytonwallet.org');
    assert.equal(getBackendTarget({ BROADCAST_GUARD_BACKEND_URL: 'https://backend.test' }), 'https://backend.test');
  });
});

describe('broadcastGuard emulation', () => {
  let emulator;
  let emulatorRequests;
  let emulatedTransactions;
  let emulatorRedirect;
  let guard;

  before(async () => {
    emulator = await startFakeEmulator((request) => {
      emulatorRequests.push(request);
      return emulatorRedirect ? { redirect: emulatorRedirect } : { transactions: emulatedTransactions };
    });
    guard = await startBroadcastGuard({
      upstreams: [{ env: ['ton'], port: 0, target: 'http://127.0.0.1:1', chain: 'ton' }],
      controlPort: 0,
      tonEmulatorUrl: `http://127.0.0.1:${emulator.address().port}`,
    });
  });

  after(async () => {
    await guard.close();
    await new Promise((resolve) => emulator.close(resolve));
  });

  beforeEach(async () => {
    emulatorRequests = [];
    emulatorRedirect = undefined;
    await fetch(`http://127.0.0.1:${guard.controlPort}/broadcasts`, { method: 'DELETE' });
  });

  it('emulates an intercepted TON send with its signature checked', async () => {
    emulatedTransactions = {
      a: buildEmulatedTransaction(TON_WALLET, 2, { aborted: false, exitCode: 0 }),
      b: buildEmulatedTransaction(TON_RECIPIENT, 3, { aborted: false, exitCode: 0 }),
    };
    const boc = await sendTon();

    const [broadcast] = await getEmulatedBroadcasts();

    assert.deepEqual(emulatorRequests.map((request) => [request.path, request.body.boc, request.body.ignore_chksig]), [
      ['/api/emulate/v1/emulateTrace', boc, false],
    ]);
    assert.equal(broadcast.emulation.isAccepted, true);
    assert.equal(broadcast.emulation.totalFees, '200');
    assert.match(await (await fetch(`http://127.0.0.1:${guard.controlPort}/`)).text(), /accepted/);
  });

  it('reports a transaction the chain would abort', async () => {
    emulatedTransactions = { a: buildEmulatedTransaction(TON_WALLET, 2, { aborted: true, exitCode: 35 }) };
    await sendTon();

    const [broadcast] = await getEmulatedBroadcasts();

    assert.equal(broadcast.emulation.isAccepted, false);
    assert.equal(broadcast.emulation.error, `${TON_WALLET.toRawString()} aborted, exit code 35`);
  });

  it('does not follow a redirect with the signed message', async () => {
    emulatorRedirect = `http://127.0.0.1:${emulator.address().port}/elsewhere`;
    await sendTon();

    const [broadcast] = await getEmulatedBroadcasts();

    assert.equal(broadcast.emulation.isAccepted, false);
    assert.match(broadcast.emulation.error, /redirect/);
    assert.equal(emulatorRequests.length, 1);
  });

  it('escapes the emulator answer on the control page', async () => {
    emulatedTransactions = { a: { ...buildEmulatedTransaction(TON_WALLET, 2, { aborted: false, exitCode: 0 }), account: '<img src=x>' } };
    await sendTon();
    await getEmulatedBroadcasts();

    const page = await (await fetch(`http://127.0.0.1:${guard.controlPort}/`)).text();

    assert.doesNotMatch(page, /<img/);
  });

  async function sendTon() {
    const boc = buildTonExternalBoc();
    await postJson(guard.ports[0], '/api/v2/jsonRPC', { id: 1, jsonrpc: '2.0', method: 'sendBoc', params: { boc } });
    return boc;
  }

  async function getEmulatedBroadcasts() {
    return (await fetch(`http://127.0.0.1:${guard.controlPort}/broadcasts?chain=ton&emulated=1`)).json();
  }
});

function buildEmulatedTransaction(account, lt, { aborted, exitCode }) {
  return {
    account: account.toRawString(),
    lt: String(lt),
    total_fees: '100',
    description: { aborted, compute_ph: { skipped: false, success: !aborted, exit_code: exitCode } },
  };
}

function startFakeEmulator(answer) {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const chunks = [];
      req.on('data', (chunk) => chunks.push(chunk));
      req.on('end', () => {
        const response = answer({ path: req.url, body: JSON.parse(Buffer.concat(chunks).toString()) });
        if (response.redirect) {
          res.writeHead(307, { location: response.redirect });
          res.end();
          return;
        }
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify(response));
      });
    });
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}
