import { getBase58Decoder, getBase58Encoder } from '@solana/kit';
import { Transaction as BtcTransaction } from '@scure/btc-signer';
import { Address, Cell, loadMessage, loadMessageRelaxed } from '@ton/core';
import { Transaction as EvmTransaction } from 'ethers';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const HOST = '127.0.0.1';
const CONTROL_PORT = 8790;
// The app also reports sessions and install attribution to this backend, so a test run must never reach production
const DEFAULT_BACKEND_URL = 'https://api-beta.mytonwallet.org';
const DEFAULT_UPSTREAMS = getDefaultUpstreams(process.env);
const TON_SEND_METHODS = new Set(['sendBoc', 'sendBocReturnHash', 'sendBocReturnHashNoError']);
const TON_SEND_PATH = /\/api\/v2\/sendBoc|\/api\/v3\/message$|\/v2\/blockchain\/message$/i;
// Any other path that names a send is refused on every host, whatever its form or method
const SEND_LIKE_PATH = /send|broadcast|submit|\/message$/i;
const TRON_SEND_PATH = /\/wallet\/broadcasttransaction$/i;
const RPC_CHAINS = new Set(['ton', 'tron', 'solana', 'evm', 'utxo']);
// The app never sends hex, so a hex broadcast is refused rather than decoded
const TRON_HEX_SEND_PATH = /\/wallet\/broadcasthex$/i;
// Blockbook also takes `GET /api/v2/sendtx/<hex>`, which the app never uses, so that form is refused
const UTXO_SEND_PATH = /\/api\/v2\/sendtx$/i;
const UTXO_GET_SEND_PATH = /\/api\/(v\d+\/)?sendtx\//i;
const JETTON_TRANSFER_OP = 0x0f8a7ea5;
const JETTON_BURN_OP = 0x595f07bc;
const TEXT_COMMENT_OP = 0;
const ENCRYPTED_COMMENT_OP = 0x2167da4b;
const W5_SIGNED_EXTERNAL_OP = 0x7369676e;
const W5_SEND_MESSAGE_ACTION = 0x0ec3c86d;
const WALLET_SIGNATURE_BITS = 512;
// Paying fees apart and ignoring errors; modes 32, 64 and 128 move value or destroy the wallet beyond the message
const PASSABLE_SEND_MODES = 0b11;
const DIESEL_SEND_PATH = /\/diesel(\/w5)?\/sendBoc$/i;
// Relayed sends the guard cannot answer convincingly, so they are recorded and refused instead of reaching the chain
const BLOCKED_BACKEND_PATHS = [
  { path: /\/diesel\/solana\/signAndSend$/, chain: 'solana' },
  { path: /\/diesel\/evm\/send$/, chain: 'evm' },
];
// Any other backend POST is refused, so a new endpoint that relays a signed action, like `/swap/execute`, fails closed
const BACKEND_POST_READS = new RegExp('^/(?:' + [
  'account-config',
  'accountStates',
  'assets',
  'attribution/[\\w-]+',
  'diesel(?:/\\w+)?/estimate',
  'nfts/report',
  'notifications/[\\w/-]+',
  'onramp-url',
  'perps/(?:activities|assets?|asset/chart|positions|position/open|(?:[\\w-]+/)*(?:build|estimate))',
  'prices/[\\w:-]+(?:/[\\w:-]+)*',
  'staking/[\\w:-]+(?:/[\\w:-]+)*',
  'swap/(?:assets|pairs|estimate|buildTransaction|cex/validate-address|history/[\\w:-]+(?:/[\\w:-]+)*|layerzero/[\\w:-]+/[\\w:-]+/refresh)',
].join('|') + ')$');
const BLOCKED_RPC_METHODS = { evm: new Set(['wallet_sendPreparedCalls', 'eth_sendUserOperation']) };
// Unknown send-like methods, such as `eth_sendBundle`, are refused rather than forwarded
const RPC_SEND_LIKE_METHOD = /send|broadcast|submit/i;
const RPC_SEND_METHODS = { ton: TON_SEND_METHODS, evm: new Set(['eth_sendRawTransaction']), solana: new Set(['sendTransaction']) };
const SEND_PATHS = {
  ton: TON_SEND_PATH, tron: new RegExp(`${TRON_SEND_PATH.source}|${TRON_HEX_SEND_PATH.source}`, 'i'), utxo: UTXO_SEND_PATH,
};
const BLOCKED_ERROR = 'Blocked by the broadcast guard';
const FAILED_ERROR = 'Failed by the broadcast guard';
const FAILURE_MODES = new Set(['offline', 'error', 'slow']);
// The longest delay `setTimeout` keeps; a longer one fires at once
const MAX_TIMER_MS = 2 ** 31 - 1;
// A case killed before its `onFlowComplete` leaves its failure behind, so each one lapses on its own
const DEFAULT_FAILURE_TTL_MS = 15 * 60 * 1000;
const failedAnswers = new WeakSet();
const DROPPED_FAILURE_MODES = new Set(['offline', 'error']);
const HOP_BY_HOP_HEADERS = new Set([
  'host', 'connection', 'content-length', 'content-encoding', 'transfer-encoding', 'accept-encoding', 'keep-alive',
]);
const BODYLESS_METHODS = new Set(['GET', 'HEAD']);
const JSON_HEADERS = { 'content-type': 'application/json', 'access-control-allow-origin': '*' };
const EMULATION_WAIT_MS = 20000;
// Parallel test cases read the same wallet at once and trip the upstreams' rate limits
const RATE_LIMIT_RETRIES = 3;
const RATE_LIMIT_MAX_WAIT_MS = 4000;
// Only a local test app gets CORS from the guard; any other page keeps the upstream's own policy
const LOCAL_ORIGIN_REGEX = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/;
// The upstream's expose list stays, so the app reads headers such as `X-Snapshot-At`
const REPLACED_CORS_HEADERS = new Set(['access-control-allow-origin', 'access-control-allow-credentials']);
const EMULATION_PATH = '/api/emulate/v1/emulateTrace';
const BACKEND_CONFIG_PATH = /^\/utils\/get-config$/i;
// The backend closes swaps by region through these flags; Android reads `isLimited`, iOS the pair.
// An iOS build that is sent `restrictedFeatures` reads that list instead of both flags.
const openSwaps = (config) => ({
  ...config,
  isLimited: false,
  isSwapAndOnRampLimited: false,
  ...('restrictedFeatures' in config && { restrictedFeatures: [] }),
});
// Parallel cases reading the same wallet share one upstream answer instead of tripping its rate limit
const DEFAULT_READ_CACHE_MS = 2000;
// Emulations and estimates depend on the payload and the current chain state, so they are never shared
const UNCACHED_READ = /emulat|simulat|estimat/i;
// Toncenter v3 reads carry a unique `_` to defeat the WebView cache
const READ_CACHE_IGNORED_PARAMS = ['_'];
// Upstreams may echo the origin into CORS headers or answer per API key, so these split cached answers
const READ_CACHE_KEY_HEADERS = ['origin', 'authorization', 'x-api-key'];

if (import.meta.url === pathToFileURL(process.argv[1]).href && process.argv.includes('--env')) {
  // For a build on another machine than the guard, such as CI, where every shard runs its own guard
  console.log(getEnvLines(DEFAULT_UPSTREAMS).join('\n'));
} else if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const guard = await startBroadcastGuard({
    upstreams: DEFAULT_UPSTREAMS,
    controlPort: CONTROL_PORT,
    logPath: process.env.BROADCAST_GUARD_LOG,
    tonEmulatorUrl: DEFAULT_UPSTREAMS[0].target,
    fixturesDir: process.env.BROADCAST_GUARD_FIXTURES_DIR ?? path.join(import.meta.dirname, '../maestro/fixtures'),
    recordDir: process.env.BROADCAST_GUARD_RECORD_DIR,
    recordPaths: process.env.BROADCAST_GUARD_RECORD_PATHS,
    readCacheMs: Number(process.env.BROADCAST_GUARD_READ_CACHE_MS || DEFAULT_READ_CACHE_MS),
    passTon: getPassTonPolicy(process.env),
    shouldKeepSwapLimits: process.env.BROADCAST_GUARD_KEEP_SWAP_LIMITS === '1',
  });
  console.log('Build the app with:\n');
  console.log(guard.envLines.join('\n'));
  console.log(`\nIntercepted broadcasts: http://${HOST}:${guard.controlPort}/ (JSON: /broadcasts)`);
  if (guard.passTon) {
    console.log(`Passes to mainnet at most ${guard.passTon.maxCount} TON broadcasts of one wallet`);
  }
}

/**
 * Proxies mainnet API hosts with every read passed through and every broadcast answered locally, so an E2E case
 * signs a real transaction that never reaches the chain. One port per host keeps the app's per-origin throttling.
 * With `tonEmulatorUrl`, every intercepted TON message is also emulated there with its signature checked, which shows
 * whether the chain would have accepted it.
 * Fixtures set through the control port answer matching reads instead of the upstream, so a case can show the app
 * any state; `POST /fixtures?load=<name>` adds the ones in `<fixturesDir>/<name>.json`. With `recordDir`, real
 * answers to `recordPaths` are saved there to start fixtures from.
 * With `readCacheMs`, identical chain reads in flight or answered successfully within that time reach the upstream
 * once, with the exceptions listed in `maestro/WRITING_FLOWS.md`; a cache hit saves no recording.
 * With `passTon`, a TON broadcast from `passTon.from` within its limits reaches mainnet instead, see
 * "Real mainnet operations" in `maestro/WRITING_FLOWS.md`.
 * The backend config the app reads says swaps are open in its region, unless `shouldKeepSwapLimits` is set.
 * A failure added through `PUT /failure` makes the TON broadcasts whose messages carry its comment fail as a host that
 * is offline, broken or slow would, still recorded, until `DELETE /failure?comment=<comment>` or its `ttlMs`.
 */
export async function startBroadcastGuard({
  upstreams, controlPort, logPath, tonEmulatorUrl, fixturesDir, recordDir, recordPaths, readCacheMs, passTon,
  shouldKeepSwapLimits,
}) {
  const broadcasts = [];
  const proxiedCounts = {};
  const fixtures = [];
  const recordPattern = recordDir && new RegExp(recordPaths || '.');
  if (recordDir) fs.mkdirSync(recordDir, { recursive: true });
  const servers = [];
  const passedTonHashes = new Set();
  const failures = [];

  function log(entry) {
    if (logPath) fs.appendFileSync(logPath, `${JSON.stringify(entry)}\n`);
  }

  function record({ boc, ...broadcast }) {
    const entry = { at: new Date().toISOString(), ...broadcast };
    broadcasts.push(entry);
    log(entry);
    console.log(`Intercepted ${entry.chain} broadcast ${entry.hash}`);

    if (entry.chain !== 'ton' || !tonEmulatorUrl) return;
    if (entry.details.isPassed && !entry.details.isDry) {
      // The chain has taken the wallet's seqno by the time an emulation would run
      entry.emulation = { status: 'skipped', error: 'passed to mainnet' };
      return;
    }
    if (entry.details.isGasless) {
      // A W5 gasless body is signed for the relayer's internal message, which the wallet rejects as an external one
      entry.emulation = { status: 'skipped', error: 'gasless, relayed by the backend' };
      return;
    }
    entry.emulation = { status: 'pending' };
    entry.emulated = emulateTonBoc(tonEmulatorUrl, boc).then((emulation) => {
      entry.emulation = emulation;
      log({ hash: entry.hash, emulation });
      console.log(`Emulated ${entry.hash}: ${emulation.isAccepted ? 'accepted' : `rejected (${emulation.error})`}`);
    });
  }

  // `pass` sends it to mainnet, `dry` answers it as usual although it would have passed, `refuse` fails it, `intercept`
  // answers it as usual. Counted when decided, so broadcasts in flight together cannot exceed
  // `maxCount`; a resent message takes no second slot.
  function decideTonBroadcast(boc, details) {
    if (!passTon?.from || !Address.parseRaw(details.from).equals(passTon.from)) return 'intercept';
    if (passedTonHashes.has(details.hash)) return passTon.isDry ? 'dry' : 'pass';
    if (passedTonHashes.size >= passTon.maxCount) return 'refuse';

    const sends = readTonWalletSends(loadMessage(Cell.fromBase64(boc).beginParse()).body);
    const isPassable = sends?.length && sends.every(({ mode, message }) => (
      (mode & ~PASSABLE_SEND_MODES) === 0 && message.info.type === 'internal' && !message.info.value.other?.size
    ));
    if (!isPassable) return 'refuse';

    const nanotons = sends.reduce((sum, { message }) => sum + message.info.value.coins, 0n);
    const isJettonWithinLimit = sends.every(({ message }) => {
      const jettonUnits = readJettonUnits(message.body);
      if (!jettonUnits) return true;
      return jettonUnits.amount !== undefined && jettonUnits.amount <= (jettonUnits.op === JETTON_BURN_OP
        ? passTon.maxBurnUnits
        : passTon.maxJettonUnits);
    });
    if (nanotons > passTon.maxNanoton || !isJettonWithinLimit) return 'refuse';

    passedTonHashes.add(details.hash);
    return passTon.isDry ? 'dry' : 'pass';
  }

  function saveResponse(upstream, req, url, status, body) {
    const target = url.pathname + url.search;
    if (!recordPattern?.test(target)) return;

    let parsed;
    try {
      parsed = JSON.parse(body.toString());
    } catch {
      return;
    }
    const name = `${Date.now()}-${upstream.chain}-${target.replace(/[^\w.-]+/g, '_').slice(0, 120)}.json`;
    const fixture = { chain: upstream.chain, method: req.method, path: target, status, body: parsed };
    fs.writeFileSync(path.join(recordDir, name), `${JSON.stringify(fixture, undefined, 2)}\n`);
  }

  const envLines = [];
  for (const upstream of upstreams) {
    const readCache = readCacheMs > 0 ? createReadCache(readCacheMs) : undefined;
    const server = await listen(upstream.port, (req, res) => {
      proxiedCounts[upstream.chain] = (proxiedCounts[upstream.chain] ?? 0) + 1;
      void handleProxyRequest(upstream, req, res, withFailures(res, failures, {
        record, fixtures, saveResponse, readCache, decideTonBroadcast, shouldKeepSwapLimits,
      }));
    });
    servers.push(server);
    envLines.push(...getEnvLines([{ ...upstream, port: server.address().port }]));
  }

  const control = await listen(controlPort, (req, res) => {
    handleControlRequest(req, res, broadcasts, proxiedCounts, {
      fixtures, fixturesDir, passTon, failures,
    }).catch((err) => {
      if (!res.headersSent) sendJson(res, { error: String(err) }, 400);
    });
  });
  servers.push(control);

  return {
    broadcasts,
    envLines,
    passTon,
    controlPort: control.address().port,
    ports: servers.slice(0, -1).map((server) => server.address().port),
    // A held `slow` answer would keep its connection, and so `close`, open until its delay ends
    close: () => Promise.all(servers.map((server) => new Promise((resolve) => {
      server.close(resolve);
      server.closeAllConnections();
    }))),
  };
}

async function handleProxyRequest(upstream, req, res, {
  record, fixtures, saveResponse, readCache, decideTonBroadcast, getIsBroadcastDropped, shouldKeepSwapLimits,
}) {
  try {
    // A browser app is served from another local port, and an upstream allows CORS only for its own origins
    if (req.method === 'OPTIONS' && getIsLocalOrigin(req.headers.origin)) {
      res.writeHead(204, {
        ...getCorsHeaders(req.headers.origin),
        'access-control-allow-methods': 'GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS',
        'access-control-allow-headers': req.headers['access-control-request-headers'] || '*',
        'access-control-max-age': '600',
      });
      res.end();
      return;
    }

    const body = await readBody(req);
    // Joined to the origin rather than resolved, so a `//other-host/` target cannot pick the upstream
    const url = new URL(`${new URL(upstream.target).origin}${req.url.startsWith('/') ? '' : '/'}${req.url}`);
    const sendPath = canonicalizePath(url.pathname);
    if (sendPath === undefined || hasHiddenRpc(upstream.chain, req, body)) {
      record({ chain: upstream.chain, hash: undefined, details: { isBlocked: true, method: req.method, path: url.pathname } });
      sendJson(res, { error: BLOCKED_ERROR }, 503);
      return;
    }

    if (req.method === 'POST' && upstream.chain === 'tron' && TRON_SEND_PATH.test(sendPath)) {
      const transaction = JSON.parse(body.toString());
      record({ chain: 'tron', hash: transaction.txID, details: describeTronTransaction(transaction) });
      sendJson(res, { result: true, txid: transaction.txID });
      return;
    }

    if (req.method === 'POST' && upstream.chain === 'tron' && TRON_HEX_SEND_PATH.test(sendPath)) {
      record({ chain: 'tron', hash: undefined, details: { isBlocked: true, path: url.pathname } });
      sendJson(res, { error: BLOCKED_ERROR }, 503);
      return;
    }

    if (req.method === 'POST' && upstream.chain === 'utxo' && UTXO_SEND_PATH.test(sendPath)) {
      const { id, outputs } = describeUtxoTransaction(body.toString().trim());
      record({ chain: 'utxo', hash: id, details: { outputs } });
      sendJson(res, { result: id });
      return;
    }

    if (req.method === 'POST' && upstream.chain === 'ton' && TON_SEND_PATH.test(sendPath)) {
      const { boc } = JSON.parse(body.toString());
      const details = describeTonBoc(boc);
      const decision = decideTonBroadcast(boc, details);
      if (decision === 'pass') {
        record({ chain: 'ton', hash: details.hash, details: { ...details, isPassed: true }, boc });
        // Only the inspected message goes on: a tonapi body may carry a `batch` of others, the query anything
        await forward(new URL(url.pathname, url.origin), req, res, Buffer.from(JSON.stringify({ boc })), { canRetry: false });
        return;
      }
      if (decision === 'refuse') {
        record({ chain: 'ton', hash: details.hash, details: { ...details, isBlocked: true }, boc });
        sendJson(res, { error: BLOCKED_ERROR }, 503);
        return;
      }
      const dryDetails = decision === 'dry' ? { isPassed: true, isDry: true } : {};
      record({ chain: 'ton', hash: details.hash, details: { ...details, ...dryDetails }, boc });
      sendJson(res, { message_hash: details.hash });
      return;
    }

    if (req.method === 'POST' && upstream.chain === 'backend' && DIESEL_SEND_PATH.test(sendPath)) {
      const { boc } = JSON.parse(body.toString());
      const details = { ...describeTonBoc(boc), isGasless: true };
      record({ chain: 'ton', hash: details.hash, details, boc });
      sendJson(res, { result: 'ok' });
      return;
    }

    const blocked = upstream.chain === 'backend'
      && BLOCKED_BACKEND_PATHS.find(({ path }) => path.test(sendPath));
    if (req.method === 'POST' && blocked) {
      record({ chain: blocked.chain, hash: undefined, details: { isGasless: true, isBlocked: true, path: url.pathname } });
      sendJson(res, { error: BLOCKED_ERROR }, 503);
      return;
    }

    const isUnknownBackendPost = upstream.chain === 'backend' && !BODYLESS_METHODS.has(req.method)
      && req.method !== 'OPTIONS' && !BACKEND_POST_READS.test(sendPath);
    const isOtherSendForm = (upstream.chain === 'utxo' && UTXO_GET_SEND_PATH.test(sendPath))
      || (req.method !== 'POST' && SEND_PATHS[upstream.chain]?.test(sendPath))
      // Backend POSTs are covered by the read allow-list above, its other methods are not
      || (SEND_LIKE_PATH.test(sendPath) && (upstream.chain !== 'backend' || req.method !== 'POST'));
    if (isUnknownBackendPost || isOtherSendForm) {
      record({ chain: upstream.chain, hash: undefined, details: { isBlocked: true, method: req.method, path: url.pathname } });
      sendJson(res, { error: BLOCKED_ERROR }, 503);
      return;
    }

    const rpc = BODYLESS_METHODS.has(req.method) ? undefined : parseJsonRpc(body);
    // A fixture for a read on a JSON-RPC path must not answer a send in the same body
    const hasRpcSend = rpc && [].concat(rpc).some((call) => isJsonRpcSend(upstream.chain, call));
    const fixture = !hasRpcSend && findFixture(fixtures, upstream.chain, req.method, url);
    if (fixture) {
      sendJson(res, fixture.body, fixture.status ?? 200);
      return;
    }

    // A backend write may record something, such as attribution or a report, so a rate-limited one is not resent
    const canRetry = upstream.chain !== 'backend' || BODYLESS_METHODS.has(req.method);
    const onResponse = (status, responseBody) => {
      // A read the upstream refused leaves the app loading, so the log shows which host and path it was
      if (status >= 400) console.error(`${upstream.chain} ${req.method} ${url.pathname.slice(0, 80)}: HTTP ${status}`);
      saveResponse(upstream, req, url, status, responseBody);
    };
    if (!shouldKeepSwapLimits && upstream.chain === 'backend' && req.method === 'GET' && BACKEND_CONFIG_PATH.test(sendPath)) {
      await forwardPatchedJson(url, req, res, openSwaps, onResponse);
      return;
    }
    // Backend answers also vary by `X-App-*` headers, so only chain hosts share reads
    const isCacheableRead = RPC_CHAINS.has(upstream.chain) && (req.method === 'GET' || (rpc && !hasRpcSend))
      && !UNCACHED_READ.test(sendPath) && ![].concat(rpc ?? []).some((call) => UNCACHED_READ.test(call?.method));
    const cache = isCacheableRead ? readCache : undefined;
    if (rpc) {
      await handleJsonRpc(upstream, url, req, res, body, rpc, { record, decideTonBroadcast, getIsBroadcastDropped }, {
        onResponse, canRetry, readCache: cache,
      });
      return;
    }

    await forward(url, req, res, body, { onResponse, canRetry, readCache: cache });
  } catch (err) {
    // Decoders quote their input, which may be a signed transaction, so only the error's kind is logged and returned
    const kind = [err?.name, err?.code].filter(Boolean).join(' ') || 'Error';
    console.error(`${upstream.chain} ${req.method} ${req.url.split('?')[0].slice(0, 80)}: ${kind}`);
    if (!res.headersSent) sendJson(res, { error: kind }, 502);
  }
}

async function handleJsonRpc(
  upstream, url, req, res, body, rpc, { record, decideTonBroadcast, getIsBroadcastDropped }, forwardOptions,
) {
  const calls = Array.isArray(rpc) ? rpc : [rpc];
  const broadcasts = calls.map((call) => interceptJsonRpcCall(upstream.chain, call));
  // A host that is down takes none of the batch, so a send beside a failed one is never passed and takes no pass slot
  const present = broadcasts.filter(Boolean);
  const dropped = present.filter((broadcast) => getIsBroadcastDropped(broadcast.details));
  if (dropped.length) {
    // The first recorded failure sets the answer, so a dropped one goes ahead of a `slow` one
    for (const broadcast of [...dropped, ...present.filter((broadcast) => !dropped.includes(broadcast))]) {
      record({ chain: upstream.chain, hash: broadcast.hash, details: broadcast.details, boc: broadcast.boc });
    }
    return;
  }

  const answers = new Map();
  // A passed send goes on with only the method and message it was checked for
  const passedCalls = new Map();

  for (const [index, call] of calls.entries()) {
    const broadcast = broadcasts[index];
    if (!broadcast) continue;

    const decision = upstream.chain === 'ton' && broadcast.boc
      ? decideTonBroadcast(broadcast.boc, broadcast.details)
      : 'intercept';
    if (decision === 'pass') {
      passedCalls.set(call, { jsonrpc: '2.0', id: call.id, method: call.method, params: { boc: broadcast.boc } });
      record({ chain: 'ton', hash: broadcast.hash, details: { ...broadcast.details, isPassed: true }, boc: broadcast.boc });
      continue;
    }
    if (decision === 'refuse') {
      record({ chain: 'ton', hash: broadcast.hash, details: { ...broadcast.details, isBlocked: true }, boc: broadcast.boc });
      answers.set(call, { jsonrpc: '2.0', id: call.id, error: { code: -32000, message: BLOCKED_ERROR } });
      continue;
    }

    const dryDetails = decision === 'dry' ? { isPassed: true, isDry: true } : {};
    record({ chain: upstream.chain, hash: broadcast.hash, details: { ...broadcast.details, ...dryDetails }, boc: broadcast.boc });
    answers.set(call, broadcast.error
      ? { jsonrpc: '2.0', id: call.id, error: broadcast.error }
      : { jsonrpc: '2.0', id: call.id, result: broadcast.result });
  }

  if (!answers.size && !passedCalls.size) {
    await forward(url, req, res, body, forwardOptions);
    return;
  }

  // A send that reached the chain is never repeated, and its reply is never cached
  const options = passedCalls.size ? { ...forwardOptions, canRetry: false, readCache: undefined } : forwardOptions;
  const rest = calls.filter((call) => !answers.has(call)).map((call) => passedCalls.get(call) ?? call);
  let forwarded = [];
  if (rest.length) {
    const response = await fetchUpstream(url, {
      method: 'POST',
      headers: buildForwardHeaders(req.headers),
      body: JSON.stringify(Array.isArray(rpc) ? rest : rest[0]),
      redirect: 'manual',
    }, options.canRetry);
    if (response.status >= 400) console.error(`${upstream.chain} ${req.method} ${url.pathname.slice(0, 80)}: HTTP ${response.status}`);
    // Following a redirect would hand the rest of the batch to a host the guard does not see
    if (response.status >= 300 && response.status < 400) {
      sendJson(res, { error: 'Blocked a redirect of a JSON-RPC batch' }, 502);
      return;
    }
    forwarded = [].concat(await response.json());
  }

  // Batch replies may come back in any order, so they are matched by id when every reply carries one
  const forwardedById = new Map(forwarded.map((reply) => [reply?.id, reply]));
  const isById = rest.every((call) => call.id !== undefined && forwardedById.has(call.id));
  const merged = calls.map((call) => answers.get(call) ?? (isById ? forwardedById.get(call.id) : forwarded.shift()));
  sendJson(res, Array.isArray(rpc) ? merged : merged[0]);
}

function canonicalizePath(pathname) {
  // Servers decode, collapse slashes, drop `;params` and ignore a trailing slash, so sends are matched on that form
  try {
    const decoded = decodeURIComponent(pathname).replace(/;[^/]*/g, '');
    return path.posix.normalize(decoded.replace(/\\/g, '/')).replace(/\/+$/, '');
  } catch {
    return undefined;
  }
}

function hasHiddenRpc(chain, req, body) {
  // A body the guard cannot read for sends is refused on chain hosts rather than forwarded
  if (!RPC_CHAINS.has(chain) || BODYLESS_METHODS.has(req.method) || !body.length) return false;
  if (req.headers['content-encoding'] && req.headers['content-encoding'] !== 'identity') return true;
  const text = body.toString().replace(/^\uFEFF/, '');
  if (!/^\s*[[{]/.test(text)) return false;
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    return true;
  }
  // A duplicate key may be read first-wins upstream, and nested batches are not inspected
  return [].concat(parsed).some((call) => Array.isArray(call) || (call && 'method' in call && typeof call.method !== 'string'))
    || hasDuplicateKey(text);
}

function hasDuplicateKey(json) {
  const objects = [];
  let isKeyNext = false;
  for (let i = 0; i < json.length; i++) {
    const char = json[i];
    if (char === '"') {
      let end = i + 1;
      while (json[end] !== '"') end += json[end] === '\\' ? 2 : 1;
      if (isKeyNext) {
        const key = JSON.parse(json.slice(i, end + 1));
        if (objects.at(-1).has(key)) return true;
        objects.at(-1).add(key);
        isKeyNext = false;
      }
      i = end;
    } else if (char === '{') {
      objects.push(new Set());
      isKeyNext = true;
    } else if (char === '[') {
      objects.push(undefined);
    } else if (char === '}' || char === ']') {
      objects.pop();
    } else if (char === ',') {
      isKeyNext = objects.at(-1) !== undefined;
    }
  }
  return false;
}

function isJsonRpcSend(chain, call) {
  const method = call?.method;
  return typeof method === 'string' && (
    BLOCKED_RPC_METHODS[chain]?.has(method) || RPC_SEND_METHODS[chain]?.has(method) || RPC_SEND_LIKE_METHOD.test(method)
  );
}

function interceptJsonRpcCall(chain, call) {
  if (BLOCKED_RPC_METHODS[chain]?.has(call.method)) {
    return {
      details: { isGasless: true, isBlocked: true, method: call.method },
      error: { code: -32000, message: BLOCKED_ERROR },
    };
  }

  if (chain === 'ton' && TON_SEND_METHODS.has(call.method)) {
    const details = describeTonBoc(call.params.boc);
    return {
      hash: details.hash, details, boc: call.params.boc, result: { '@type': 'raw.extMessageInfo', hash: details.hash },
    };
  }

  if (chain === 'evm' && call.method === 'eth_sendRawTransaction') {
    const transaction = EvmTransaction.from(call.params[0]);
    return {
      hash: transaction.hash,
      result: transaction.hash,
      details: {
        chainId: transaction.chainId.toString(),
        from: transaction.from,
        to: transaction.to,
        amount: transaction.value.toString(),
        data: transaction.data,
      },
    };
  }

  if (chain === 'solana' && call.method === 'sendTransaction') {
    const signature = getSolanaSignature(call.params[0], call.params[1]?.encoding);
    return { hash: signature, result: signature, details: {} };
  }

  if (RPC_SEND_LIKE_METHOD.test(call.method)) {
    return { details: { isBlocked: true, method: call.method }, error: { code: -32000, message: BLOCKED_ERROR } };
  }

  return undefined;
}

async function emulateTonBoc(emulatorUrl, boc) {
  try {
    const response = await fetch(new URL(EMULATION_PATH, emulatorUrl), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      // Unlike the app's fee estimate, the signature is checked: that is what the chain would do
      body: JSON.stringify({ boc, ignore_chksig: false, include_code_data: false, with_actions: false }),
      // A followed redirect would hand the signed message to a host that may broadcast it
      redirect: 'manual',
    });
    if (response.status >= 300 && response.status < 400) {
      return { status: 'failed', isAccepted: false, error: `Refused a redirect (HTTP ${response.status})`, transactions: [] };
    }
    const result = await response.json();
    if (!response.ok || !result.transactions) {
      return { status: 'done', isAccepted: false, error: result.error ?? `HTTP ${response.status}`, transactions: [] };
    }

    return summarizeEmulation(result);
  } catch (err) {
    return { status: 'failed', isAccepted: false, error: String(err), transactions: [] };
  }
}

function summarizeEmulation(result) {
  const transactions = Object.values(result.transactions)
    .sort((a, b) => Number(BigInt(a.lt) - BigInt(b.lt)))
    .map(({ account, total_fees: fees, description, in_msg: inMessage }) => ({
      account,
      fees,
      value: inMessage?.value ?? undefined,
      isAborted: description.aborted,
      computeExitCode: description.compute_ph?.skipped ? undefined : description.compute_ph?.exit_code,
      actionResultCode: description.action?.result_code,
    }));
  const failed = transactions.find((transaction) => transaction.isAborted);

  return {
    status: 'done',
    isAccepted: transactions.length > 0 && !failed,
    error: failed && `${failed.account} aborted, exit code ${failed.computeExitCode ?? '-'}`,
    totalFees: transactions.reduce((sum, transaction) => sum + BigInt(transaction.fees), 0n).toString(),
    transactions,
  };
}

function renderBroadcastsPage(broadcasts, proxiedCounts) {
  const rows = broadcasts.slice().reverse().map((broadcast) => {
    const { emulation } = broadcast;
    const verdict = describeEmulation(emulation);
    const messages = (broadcast.details.messages ?? []).map((message) => (message.jetton
      ? `jetton ${message.jetton.amount} → ${message.jetton.to}`
      : `${formatTon(message.amount)} TON → ${message.to}`)).join('<br>');
    const steps = (emulation?.transactions ?? []).map((transaction) => (
      // The emulator's answer is outside data, so it is escaped like the verdict
      escapeHtml(`${transaction.isAborted ? '✗' : '✓'} ${transaction.account} exit ${transaction.computeExitCode ?? '-'}`)
    )).join('<br>');
    const color = emulation?.isAccepted ? '#1a7f37' : emulation?.status === 'pending' ? '#9a6700' : '#cf222e';

    return `<tr><td>${broadcast.at.slice(11, 19)}</td><td>${broadcast.chain}${broadcast.details.isGasless ? ' gasless' : ''}`
      + `</td><td>${messages}</td><td style="color:${color}"><b>${escapeHtml(verdict)}</b><br><small>${steps}</small></td></tr>`;
  }).join('');

  return `<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="2"><title>Broadcast guard</title>
<style>body{font:14px system-ui;margin:16px}td,th{border-bottom:1px solid #ddd;padding:6px;text-align:left;vertical-align:top}
small{color:#555;font-family:monospace}</style>
<h2>Intercepted broadcasts</h2><p>Nothing here reached the chain. Proxied requests: ${escapeHtml(JSON.stringify(proxiedCounts))}</p>
<table><tr><th>Time</th><th>Chain</th><th>Transfers</th><th>Emulation (signature checked)</th></tr>${rows}</table>`;
}

function describeEmulation(emulation) {
  if (!emulation) return 'not emulated';
  if (emulation.status === 'skipped') return `not emulated: ${emulation.error}`;
  if (emulation.status === 'pending') return 'emulating…';
  if (emulation.isAccepted) return `accepted, fees ${formatTon(emulation.totalFees)} TON`;
  return `rejected: ${emulation.error}`;
}

function formatTon(nanotons) {
  return (Number(nanotons) / 1e9).toFixed(6);
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (char) => `&#${char.charCodeAt(0)};`);
}

function describeTonBoc(boc) {
  const root = Cell.fromBase64(boc);
  const external = loadMessage(root.beginParse());
  const wallet = readTonWallet(external.body);

  return {
    hash: root.hash().toString('base64'),
    from: external.info.dest.toRawString(),
    ...(wallet && { wallet: wallet.header }),
    // A wallet's own sends keep their order, repeats and send modes
    messages: wallet
      ? wallet.sends.filter(({ message }) => isTonInternalMessage(message))
        .map(({ message, mode }) => describeTonMessage(message, mode))
      : findTonInternalMessages(external.body),
  };
}

/**
 * The version, seqno and expiry a W5 or v4 wallet body carries, with its sends, or `undefined` for another layout.
 * A v4 body counts as one only when it reads as a plain send, the only action the app signs with v4.
 */
function readTonWallet(body) {
  try {
    const slice = body.beginParse();
    const isW5 = slice.remainingBits >= 32 && slice.preloadUint(32) === W5_SIGNED_EXTERNAL_OP;
    const sends = readTonWalletSends(body);
    if (!sends) return undefined;

    slice.skip(isW5 ? 64 : WALLET_SIGNATURE_BITS + 32); // W5: op and wallet id; v4: signature and subwallet id
    const validUntil = slice.loadUint(32);
    const seqno = slice.loadUint(32);

    return { header: { version: isW5 ? 'w5' : 'v4', seqno, validUntil }, sends };
  } catch {
    return undefined;
  }
}

/**
 * The op and amount of a jetton transfer or burn, with `amount` left out when the body does not read as one; `undefined`
 * for any other body
 */
function readJettonUnits(body) {
  const slice = body.beginParse();
  if (slice.remainingBits < 32) return undefined;
  const op = slice.loadUint(32);
  if (op !== JETTON_TRANSFER_OP && op !== JETTON_BURN_OP) return undefined;
  try {
    slice.skip(64);
    return { op, amount: slice.loadCoins() };
  } catch {
    return { op };
  }
}

/**
 * The sends a W5 or v4 wallet body asks for, in order and with repeats, or `undefined` for any other layout or action,
 * such as a W5 extension or a v4 plugin call.
 */
function readTonWalletSends(body) {
  try {
    const slice = body.beginParse();
    return slice.remainingBits >= 32 && slice.preloadUint(32) === W5_SIGNED_EXTERNAL_OP
      ? readW5Sends(slice)
      : readV4Sends(slice);
  } catch {
    return undefined;
  }
}

function readW5Sends(slice) {
  slice.skip(32 + 32 + 32 + 32); // Op, wallet id, valid until, seqno
  let actionCell = slice.loadMaybeRef();
  const hasOtherActions = slice.loadBit();
  if (hasOtherActions || slice.remainingBits !== WALLET_SIGNATURE_BITS || slice.remainingRefs) return undefined;

  const sends = [];
  while (actionCell && (actionCell.bits.length || actionCell.refs.length)) {
    const action = actionCell.beginParse();
    actionCell = action.loadRef();
    if (action.loadUint(32) !== W5_SEND_MESSAGE_ACTION) return undefined;
    const mode = action.loadUint(8);
    const cell = action.loadRef();
    sends.unshift({ mode, cell, message: loadMessageRelaxed(cell.beginParse()) });
    if (action.remainingBits || action.remainingRefs) return undefined;
  }
  return sends;
}

function readV4Sends(slice) {
  slice.skip(WALLET_SIGNATURE_BITS + 32 + 32 + 32); // Signature, subwallet id, valid until, seqno
  const isSimpleSend = slice.loadUint(8) === 0;
  if (!isSimpleSend || slice.remainingBits !== slice.remainingRefs * 8) return undefined;

  const sends = [];
  while (slice.remainingRefs) {
    const mode = slice.loadUint(8);
    const cell = slice.loadRef();
    sends.push({ mode, cell, message: loadMessageRelaxed(cell.beginParse()) });
  }
  return sends;
}

// A layout other than W5 or v4 is read by trying every cell as a message, so its messages carry no send mode
function findTonInternalMessages(body) {
  const messages = new Map();
  const queue = [body];

  while (queue.length) {
    const cell = queue.shift();
    queue.push(...cell.refs);

    try {
      const message = loadMessageRelaxed(cell.beginParse());
      if (isTonInternalMessage(message)) {
        messages.set(cell.hash().toString('hex'), describeTonMessage(message));
      }
    } catch {
      // Not a message cell
    }
  }

  return [...messages.values()];
}

function isTonInternalMessage(message) {
  return message.info.type === 'internal' && Address.isAddress(message.info.dest);
}

function describeTonMessage(message, mode) {
  const comment = describeComment(message.body);

  return {
    to: message.info.dest.toRawString(),
    amount: message.info.value.coins.toString(),
    isBounceable: message.info.bounce,
    hasStateInit: Boolean(message.init),
    ...(mode !== undefined && { mode }),
    ...(comment && { comment }),
    jetton: describeJettonTransfer(message.body),
  };
}

function describeJettonTransfer(body) {
  let slice;
  let transfer;
  try {
    slice = body.beginParse();
    if (slice.loadUint(32) !== JETTON_TRANSFER_OP) return undefined;
    slice.skip(64);
    const amount = slice.loadCoins().toString();
    transfer = { to: slice.loadAddress().toRawString(), amount };
  } catch {
    return undefined;
  }

  // The recipient and amount stand on their own when the rest of the body does not read
  try {
    slice.loadMaybeAddress(); // Response destination
    const hasCustomPayload = Boolean(slice.loadMaybeRef());
    const forwardTonAmount = slice.loadCoins().toString();
    const comment = describeComment(slice.loadBit() ? slice.loadRef() : slice.asCell());

    return { ...transfer, forwardTonAmount, hasCustomPayload, ...(comment && { comment }) };
  } catch {
    return transfer;
  }
}

/**
 * The text of a plain comment, joined across its chain of cells, or `isEncrypted` for an encrypted one, whose content
 * stays opaque; `undefined` for an empty body or any other op
 */
function describeComment(cell) {
  try {
    const slice = cell.beginParse();
    if (slice.remainingBits < 32) return undefined;
    const op = slice.loadUint(32);
    if (op === ENCRYPTED_COMMENT_OP) return { isEncrypted: true };
    if (op !== TEXT_COMMENT_OP) return undefined;

    return { text: slice.loadStringTail() };
  } catch {
    return undefined;
  }
}

function describeTronTransaction(transaction) {
  return {
    contracts: transaction.raw_data.contract.map(({ type, parameter }) => ({
      type,
      to: parameter.value.to_address ?? parameter.value.contract_address,
      amount: parameter.value.amount?.toString(),
      data: parameter.value.data,
    })),
  };
}

function describeUtxoTransaction(hex) {
  const transaction = BtcTransaction.fromRaw(Buffer.from(hex, 'hex'), {
    allowUnknownOutputs: true,
    disableScriptCheck: true,
  });
  const outputs = [];
  for (let i = 0; i < transaction.outputsLength; i++) {
    const output = transaction.getOutput(i);
    outputs.push({ script: Buffer.from(output.script).toString('hex'), amount: output.amount.toString() });
  }

  return { id: transaction.id, outputs };
}

// A wire transaction starts with a one-byte signature count while it has fewer than 128 signers
function getSolanaSignature(encoded, encoding = 'base58') {
  const bytes = encoding === 'base64'
    ? Buffer.from(encoded, 'base64')
    : getBase58Encoder().encode(encoded);

  return getBase58Decoder().decode(bytes.subarray(1, 65));
}

async function handleControlRequest(req, res, broadcasts, proxiedCounts, {
  fixtures, fixturesDir, passTon, failures,
}) {
  const url = new URL(req.url, `http://${HOST}`);
  if (url.pathname === '/fixtures') {
    await handleFixturesRequest(req, res, url, fixtures, fixturesDir);
    return;
  }

  if (url.pathname === '/failure') {
    await handleFailureRequest(req, res, url, failures);
    return;
  }

  if (url.pathname === '/pass') {
    await handlePassRequest(req, res, passTon);
    return;
  }

  if (url.pathname === '/') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(renderBroadcastsPage(broadcasts, proxiedCounts));
    return;
  }

  if (url.pathname === '/proxied') {
    sendJson(res, proxiedCounts);
    return;
  }

  if (url.pathname !== '/broadcasts') {
    sendJson(res, { error: 'Not found' }, 404);
    return;
  }

  if (req.method === 'DELETE') {
    broadcasts.length = 0;
    for (const chain of Object.keys(proxiedCounts)) delete proxiedCounts[chain];
    sendJson(res, { ok: true });
    return;
  }

  const chain = url.searchParams.get('chain');
  const to = url.searchParams.get('to');
  const matching = broadcasts.filter((broadcast) => (
    (!chain || broadcast.chain === chain) && (!to || isSentTo(broadcast, to))
  ));
  if (url.searchParams.has('emulated')) {
    await Promise.race([
      Promise.all(matching.map((broadcast) => broadcast.emulated)),
      new Promise((resolve) => { setTimeout(resolve, EMULATION_WAIT_MS); }),
    ]);
  }
  // A wallet message can carry transfers to several recipients, so a case checks amounts on these only
  sendJson(res, matching.map(({ emulated, ...broadcast }) => (
    to ? { ...broadcast, toMessages: findMessagesTo(broadcast, to) } : broadcast
  )));
}

function findMessagesTo(broadcast, to) {
  if (broadcast.chain !== 'ton') return undefined;
  const rawTo = Address.parse(to).toRawString();

  // Refused sends carry no decoded messages
  return (broadcast.details.messages ?? []).filter((message) => message.to === rawTo || message.jetton?.to === rawTo);
}

function isSentTo(broadcast, to) {
  const { chain, details } = broadcast;
  if (chain === 'ton') return findMessagesTo(broadcast, to).length > 0;
  if (chain === 'evm') return details.to?.toLowerCase() === to.toLowerCase();
  if (chain === 'tron') return Boolean(details.contracts?.some((contract) => contract.to === to));

  return false;
}

async function forward(url, req, res, body, { onResponse, canRetry, readCache }) {
  const fetchResponse = () => fetchForwarded(url, req, body, canRetry);
  const { response, isFetched } = readCache
    ? await readCache(buildReadCacheKey(url, req, body), fetchResponse)
    : { response: await fetchResponse(), isFetched: true };
  const { status, body: responseBody } = response;

  // Cached answers keep the upstream's CORS headers, so the local ones are applied at reply time
  const headers = buildReplyHeaders(response.headers, req);

  // The app would follow an absolute redirect straight to the real host, bypassing the guard
  const { location } = headers;
  if (location && (new URL(location, url).origin !== url.origin || /^\s*([a-z][\w+.-]*:|[\\/]{2})/i.test(location))) {
    sendJson(res, { error: `Blocked a redirect to ${headers.location}` }, 502);
    return;
  }
  res.writeHead(status, headers);
  res.end(responseBody);
  if (isFetched) onResponse?.(status, responseBody);
}

async function forwardPatchedJson(url, req, res, patch, onResponse) {
  const { status, headers, body: responseBody } = await fetchForwarded(url, req, Buffer.alloc(0), true);
  onResponse(status, responseBody);
  let parsed;
  try {
    parsed = JSON.parse(responseBody.toString());
  } catch {
    parsed = undefined;
  }
  const isPatchable = status < 300 && parsed && typeof parsed === 'object' && !Array.isArray(parsed);
  // A redirect is answered without its `location`, so the app never leaves the guard
  const { location, ...replyHeaders } = buildReplyHeaders(headers, req);
  if (!isPatchable) {
    res.writeHead(status, replyHeaders);
    res.end(responseBody);
    return;
  }
  // The upstream's validators describe its own body, so a cached patched answer is never revalidated against them
  const { etag, 'last-modified': lastModified, ...patchedHeaders } = replyHeaders;
  res.writeHead(status, { ...patchedHeaders, 'content-type': JSON_HEADERS['content-type'], 'cache-control': 'no-store' });
  res.end(JSON.stringify(patch(parsed)));
}

function buildReplyHeaders(upstreamHeaders, req) {
  const isLocalOrigin = getIsLocalOrigin(req.headers.origin);
  const headers = {};
  for (const [name, value] of Object.entries(upstreamHeaders)) {
    if (!(isLocalOrigin && REPLACED_CORS_HEADERS.has(name))) headers[name] = value;
  }
  if (isLocalOrigin) Object.assign(headers, getCorsHeaders(req.headers.origin));
  return headers;
}

async function fetchForwarded(url, req, body, canRetry) {
  const hasBody = !BODYLESS_METHODS.has(req.method);
  const response = await fetchUpstream(url, {
    method: req.method,
    headers: buildForwardHeaders(req.headers),
    body: hasBody ? body : undefined,
    redirect: 'manual',
  }, canRetry);

  const headers = {};
  response.headers.forEach((value, name) => {
    if (!HOP_BY_HOP_HEADERS.has(name)) headers[name] = value;
  });
  const responseBody = Buffer.from(await response.arrayBuffer());

  return { status: response.status, headers, body: responseBody };
}

function createReadCache(ttlMs) {
  const entries = new Map();

  return async function fetchCached(key, fetchResponse, isRetry = false) {
    const now = Date.now();
    const cached = entries.get(key);
    if (cached && cached.expiresAt > now) {
      const response = await cached.response.catch(() => undefined);
      if (response && isSuccessfulResponse(response)) return { response, isFetched: false };
      // A failed answer is not kept, so the requests that waited for it retry it once together
      if (!isRetry) return fetchCached(key, fetchResponse, true);
      return { response: await cached.response, isFetched: false };
    }

    for (const [otherKey, entry] of entries) {
      if (entry.expiresAt <= now) entries.delete(otherKey);
    }
    const entry = { response: fetchResponse(), expiresAt: Infinity };
    entries.set(key, entry);
    let response;
    try {
      response = await entry.response;
    } catch (err) {
      if (entries.get(key) === entry) entries.delete(key);
      throw err;
    }
    if (isSuccessfulResponse(response) && !hasSnapshotTime(response)) {
      entry.expiresAt = Date.now() + ttlMs;
    } else if (entries.get(key) === entry) {
      entries.delete(key);
    }
    return { response, isFetched: true };
  };
}

function buildReadCacheKey(url, req, body) {
  const headers = READ_CACHE_KEY_HEADERS.map((name) => req.headers[name] ?? '');
  // Filtered on the raw query, since re-encoding it would merge a literal `+` with a space
  const query = url.search.slice(1).split('&')
    .filter((param) => !READ_CACHE_IGNORED_PARAMS.includes(param.split('=')[0]))
    .join('&');

  return JSON.stringify([req.method, url.origin + url.pathname, query, ...headers, body.toString()]);
}

// A concurrent request may share such an answer, but a replayed `Date` would later make it look fresh
function hasSnapshotTime({ headers }) {
  return Boolean(headers['x-snapshot-at']);
}

function isSuccessfulResponse({ status, body }) {
  if (status < 200 || status >= 300) return false;
  let parsed;
  try {
    parsed = JSON.parse(body.toString());
  } catch {
    // Chain reads are JSON, so another body is an error page from a proxy or CDN
    return false;
  }
  // JSON-RPC hosts and toncenter report errors, including rate limits, inside a successful HTTP answer
  return [].concat(parsed).every((reply) => !reply?.error && reply?.ok !== false);
}

async function fetchUpstream(url, init, canRetry) {
  for (let attempt = 0; ; attempt++) {
    const response = await fetch(url, init);
    if (response.status !== 429 || !canRetry || attempt === RATE_LIMIT_RETRIES) return response;
    await response.arrayBuffer();
    await new Promise((resolve) => setTimeout(resolve, getRateLimitWait(response, attempt)));
  }
}

function getRateLimitWait(response, attempt) {
  const wait = getRetryAfterMs(response.headers.get('retry-after')) ?? 500 * 2 ** attempt;
  // The jitter keeps parallel retries from hitting the upstream in step again
  return Math.min(wait, RATE_LIMIT_MAX_WAIT_MS) + Math.random() * 250;
}

// The wallet whose sends may pass is set once, by the first case that reads it from the app; it never changes after
async function handlePassRequest(req, res, passTon) {
  if (!passTon) {
    sendJson(res, { error: 'The guard passes nothing to mainnet' }, 409);
    return;
  }
  if (req.method === 'POST') {
    const from = Address.parse(JSON.parse((await readBody(req)).toString()).from);
    if (passTon.from && !passTon.from.equals(from)) {
      sendJson(res, { error: 'Another wallet is already set' }, 409);
      return;
    }
    passTon.from = from;
  }
  sendJson(res, { from: passTon.from?.toRawString(), isDry: passTon.isDry });
}

// Each failure is scoped to a comment, so cases running at once against one guard fail only their own broadcasts
async function handleFailureRequest(req, res, url, failures) {
  if (req.method === 'DELETE') {
    const comment = url.searchParams.get('comment');
    removeFailures(failures, (failure) => comment === null || failure.comment === comment);
  }
  if (req.method === 'PUT' || req.method === 'POST') {
    const {
      comment, mode, delayMs, ttlMs = DEFAULT_FAILURE_TTL_MS,
    } = JSON.parse((await readBody(req)).toString());
    const isDelayValid = mode !== 'slow' || isTimerDelay(delayMs);
    if (typeof comment !== 'string' || !comment || !FAILURE_MODES.has(mode) || !isDelayValid || !isTimerDelay(ttlMs)) {
      sendJson(res, {
        error: 'A failure takes a comment, offline, error, or slow with a delayMs, and an optional ttlMs, each delay'
          + ` positive and at most ${MAX_TIMER_MS} ms`,
      }, 400);
      return;
    }
    removeFailures(failures, (failure) => failure.comment === comment);
    failures.push({
      comment, mode, ...(mode === 'slow' && { delayMs }), expiresAt: new Date(Date.now() + ttlMs).toISOString(),
    });
  }

  removeFailures(failures, isFailureExpired);
  sendJson(res, failures);
}

function isTimerDelay(ms) {
  return Number.isInteger(ms) && ms > 0 && ms <= MAX_TIMER_MS;
}

function isFailureExpired(failure) {
  return Date.parse(failure.expiresAt) <= Date.now();
}

function removeFailures(failures, predicate) {
  failures.splice(0, failures.length, ...failures.filter((failure) => !predicate(failure)));
}

/**
 * Wraps a proxy request's handlers so a TON broadcast whose message carries a failure's comment fails as that failure
 * says, and never reaches mainnet. The failure of each broadcast is fixed when the guard first decodes it, so a change
 * to `/failure` leaves the broadcasts in flight as they were.
 */
function withFailures(res, failures, handlers) {
  const failureByHash = new Map();
  const getFailure = (details) => {
    if (!failureByHash.has(details.hash)) {
      failureByHash.set(details.hash, failures.find((failure) => (
        !isFailureExpired(failure) && hasComment(details, failure.comment)
      )));
    }
    return failureByHash.get(details.hash);
  };

  return {
    ...handlers,
    getIsBroadcastDropped: (details) => DROPPED_FAILURE_MODES.has(getFailure(details)?.mode),
    decideTonBroadcast: (boc, details) => (
      getFailure(details) ? 'intercept' : handlers.decideTonBroadcast(boc, details)
    ),
    record: (broadcast) => {
      const failure = getFailure(broadcast.details);
      if (!failure) {
        handlers.record(broadcast);
        return;
      }
      handlers.record({ ...broadcast, details: { ...broadcast.details, failure: failure.mode } });
      holdFailedAnswer(res, failure);
    },
  };
}

function hasComment(details, comment) {
  return (details.messages ?? []).some((message) => (
    message.comment?.text === comment || message.jetton?.comment?.text === comment
  ));
}

/**
 * Replaces the answer to a broadcast: `offline` drops the connection unanswered, `error` answers HTTP 503, `slow` holds
 * the usual answer for `delayMs`. The whole answer fails, as it would from a host that is down, so a JSON-RPC batch
 * loses its reads too; the app sends one call per request. A batch records each of its sends, and only the first one
 * acts.
 */
function holdFailedAnswer(res, { mode, delayMs }) {
  if (failedAnswers.has(res)) return;
  failedAnswers.add(res);
  const answer = { writeHead: res.writeHead.bind(res), end: res.end.bind(res) };
  const held = [];
  let isReleased = false;
  for (const name of Object.keys(answer)) {
    res[name] = (...args) => {
      if (isReleased) return answer[name](...args);
      held.push([name, args]);
      return res;
    };
  }

  if (mode === 'offline') {
    res.socket.destroy();
  } else if (mode === 'error') {
    answer.writeHead(503, JSON_HEADERS);
    answer.end(JSON.stringify({ error: FAILED_ERROR }));
  } else {
    const timer = setTimeout(() => {
      isReleased = true;
      for (const [name, args] of held) answer[name](...args);
    }, delayMs);
    timer.unref();
    // The app gives up on a slow answer and closes the connection, which then takes nothing
    res.on('close', () => clearTimeout(timer));
  }
}

async function handleFixturesRequest(req, res, url, fixtures, fixturesDir) {
  if (req.method === 'DELETE') fixtures.length = 0;
  if (req.method === 'POST' || req.method === 'PUT') {
    const name = url.searchParams.get('load');
    const file = name && path.resolve(fixturesDir, `${name}.json`);
    if (file && !file.startsWith(path.resolve(fixturesDir) + path.sep)) {
      sendJson(res, { error: 'Fixture name escapes the fixtures folder' }, 400);
      return;
    }
    const added = [].concat(JSON.parse(file ? fs.readFileSync(file, 'utf8') : (await readBody(req)).toString()));
    const invalid = added.find((fixture) => !fixture.chain || typeof fixture.path !== 'string' || !('body' in fixture));
    if (invalid) {
      sendJson(res, { error: 'Each fixture needs chain, path and body', fixture: invalid }, 400);
      return;
    }
    if (req.method === 'PUT') fixtures.length = 0;
    fixtures.push(...added);
  }

  sendJson(res, fixtures);
}

function findFixture(fixtures, chain, method, url) {
  const target = url.pathname + url.search;
  // The latest fixture wins, so a case can override a shared one for a single state
  return fixtures.findLast((fixture) => (
    fixture.chain === chain && (fixture.method ?? 'GET') === method && new RegExp(fixture.path).test(target)
  ));
}

function buildForwardHeaders(headers) {
  return Object.fromEntries(Object.entries(headers).filter(([name]) => !HOP_BY_HOP_HEADERS.has(name)));
}

function parseJsonRpc(body) {
  try {
    const parsed = JSON.parse(body.toString().replace(/^\uFEFF/, ''));
    // Every batch member is checked, so a send behind a malformed first item is still found
    const isCall = (call) => call && typeof call.method === 'string';
    return (Array.isArray(parsed) ? parsed.some(isCall) : isCall(parsed)) ? parsed : undefined;
  } catch {
    return undefined;
  }
}

function getRetryAfterMs(value) {
  if (!value) return undefined;
  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Math.max(seconds, 0) * 1000;
  const date = Date.parse(value);
  return Number.isNaN(date) ? undefined : Math.max(date - Date.now(), 0);
}

function getIsLocalOrigin(origin) {
  return Boolean(origin) && LOCAL_ORIGIN_REGEX.test(origin);
}

function getCorsHeaders(origin) {
  return { 'access-control-allow-origin': origin, 'access-control-allow-credentials': 'true', vary: 'Origin' };
}

function sendJson(res, data, status = 200) {
  res.writeHead(status, JSON_HEADERS);
  res.end(JSON.stringify(data));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function listen(port, handler) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(handler);
    server.once('error', reject);
    server.listen(port, HOST, () => resolve(server));
  });
}

/**
 * Reads the limits under which TON broadcasts from one wallet reach mainnet, or `undefined` when nothing may pass.
 * The wallet comes from `BROADCAST_GUARD_PASS_TON_FROM` or, with `BROADCAST_GUARD_PASS_TON=1`, from the first
 * `POST /pass`; until then, nothing passes. With `BROADCAST_GUARD_PASS_TON_DRY=1` it decides as usual but sends nothing,
 * recording what would have passed with `isDry`.
 * `maxJettonUnits` caps each jetton transfer and `maxBurnUnits` each burn, in the jetton's own smallest units; an unset
 * one allows none.
 */
export function getPassTonPolicy(env) {
  if (!env.BROADCAST_GUARD_PASS_TON_FROM && env.BROADCAST_GUARD_PASS_TON !== '1') return undefined;

  const maxCount = Number(env.BROADCAST_GUARD_PASS_TON_MAX_COUNT);
  if (!Number.isInteger(maxCount) || maxCount < 1) {
    throw new Error('BROADCAST_GUARD_PASS_TON_MAX_COUNT must be a positive integer');
  }
  if (!/^\d+$/.test(env.BROADCAST_GUARD_PASS_TON_MAX_NANOTON ?? '')) {
    throw new Error('BROADCAST_GUARD_PASS_TON_MAX_NANOTON must be a number of nanotons');
  }

  return {
    from: env.BROADCAST_GUARD_PASS_TON_FROM ? Address.parse(env.BROADCAST_GUARD_PASS_TON_FROM) : undefined,
    maxNanoton: BigInt(env.BROADCAST_GUARD_PASS_TON_MAX_NANOTON),
    maxJettonUnits: readUnits(env.BROADCAST_GUARD_PASS_TON_MAX_JETTON_UNITS),
    maxBurnUnits: readUnits(env.BROADCAST_GUARD_PASS_TON_MAX_BURN_UNITS),
    maxCount,
    isDry: env.BROADCAST_GUARD_PASS_TON_DRY === '1',
  };
}

function readUnits(value) {
  return BigInt(/^\d+$/.test(value ?? '') ? value : 0);
}

export function getDefaultUpstreams(env) {
  return [
    { env: ['TONCENTER_MAINNET_URL'], port: 8791, target: 'https://toncenter.mytonwallet.org', chain: 'ton' },
    { env: ['TONAPIIO_MAINNET_URL'], port: 8792, target: 'https://tonapiio.mytonwallet.org', chain: 'ton' },
    { env: ['TRON_MAINNET_API_URL'], port: 8793, target: 'https://tronapi.mytonwallet.org', chain: 'tron' },
    {
      env: ['SOLANA_MAINNET_RPC_URL', 'SOLANA_MAINNET_API_URL'],
      port: 8794,
      target: 'https://solanaapi.mytonwallet.org',
      chain: 'solana',
    },
    { env: ['EVM_MAINNET_RPC_URL'], port: 8795, target: 'https://evmapi.mytonwallet.org', chain: 'evm' },
    { env: ['UTXO_MAINNET_RPC_URL'], port: 8796, target: 'https://utxoapi.mytonwallet.org', chain: 'utxo' },
    {
      env: ['BRILLIANT_API_BASE_URL'], port: 8797, target: env.BROADCAST_GUARD_BACKEND_URL || DEFAULT_BACKEND_URL, chain: 'backend',
    },
    // Read-only, proxied so fixtures can show the Portfolio tab's empty and error states
    {
      env: ['PORTFOLIO_API_URL'], envPath: '/api', port: 8799, target: 'https://api-portfolio.mywallet.io', chain: 'portfolio',
    },
  ];
}

function getEnvLines(upstreams) {
  return upstreams.flatMap((upstream) => upstream.env.map(
    (name) => `${name}=http://${HOST}:${upstream.port}${upstream.envPath ?? ''}`,
  ));
}
