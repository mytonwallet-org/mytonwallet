import http from 'node:http';
import https from 'node:https';
import { pathToFileURL } from 'node:url';

const HOST = '127.0.0.1';
const UPSTREAM_TIMEOUT_MS = 60000;
const PORT = 8798;
const TARGET = 'https://testnet.toncenter.com';
const HOP_BY_HOP_HEADERS = new Set([
  'host', 'connection', 'content-length', 'transfer-encoding', 'keep-alive', 'origin', 'referer',
]);
const CORS_HEADERS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-max-age': '600',
};

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!process.env.TONCENTER_TESTNET_KEY) {
    console.error('Set TONCENTER_TESTNET_KEY to a testnet.toncenter.com key');
    process.exit(1);
  }
  const proxy = await startTestnetProxy({ port: PORT, target: TARGET, apiKey: process.env.TONCENTER_TESTNET_KEY });
  console.log(`Build the app with:\n\nTONCENTER_TESTNET_URL=http://${HOST}:${proxy.port}`);
}

/**
 * Passes testnet requests to toncenter.com with our key, so testnet cases are not throttled. The mytonwallet testnet
 * host ignores the key, and toncenter.com refuses the app's own headers in CORS, so this answers CORS itself.
 * It changes nothing else: testnet sends go to the chain, unlike with the broadcast guard.
 */
export function startTestnetProxy({ port, target, apiKey }) {
  const targetUrl = new URL(target);
  const client = targetUrl.protocol === 'https:' ? https : http;
  const server = http.createServer((req, res) => {
    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        ...CORS_HEADERS,
        'access-control-allow-headers': req.headers['access-control-request-headers'] ?? '*',
      });
      res.end();
      return;
    }

    const headers = Object.fromEntries(
      Object.entries(req.headers).filter(([name]) => !HOP_BY_HOP_HEADERS.has(name)),
    );
    // Joined to the origin rather than resolved, so a `//other-host/` path cannot send our key elsewhere
    const upstream = client.request(new URL(`${targetUrl.origin}${req.url.startsWith('/') ? '' : '/'}${req.url}`), {
      method: req.method,
      headers: { ...headers, 'x-api-key': apiKey },
    }, (response) => {
      // The app would follow a redirect itself, sending a signed transfer past the proxy to any host
      if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
        response.resume();
        res.writeHead(502, { 'content-type': 'application/json', ...CORS_HEADERS });
        res.end(JSON.stringify({ error: 'Refused an upstream redirect' }));
        return;
      }
      const responseHeaders = { ...response.headers, ...CORS_HEADERS };
      delete responseHeaders['access-control-allow-credentials'];
      res.writeHead(response.statusCode, responseHeaders);
      // Piped rather than buffered, so streaming answers reach the app as they come
      response.pipe(res);
      // An upstream that drops mid-answer would otherwise leave the app waiting forever
      response.on('aborted', () => res.destroy());
      response.on('error', () => res.destroy());
    });
    upstream.setTimeout(UPSTREAM_TIMEOUT_MS, () => upstream.destroy(new Error('Upstream timed out')));
    res.on('close', () => {
      if (!res.writableFinished) upstream.destroy();
    });
    upstream.on('error', (err) => {
      // Mid-answer, an error body would be glued to the partial answer, so the connection is cut instead
      if (res.headersSent) {
        res.destroy();
        return;
      }
      res.writeHead(502, { 'content-type': 'application/json', ...CORS_HEADERS });
      res.end(JSON.stringify({ error: String(err) }));
    });
    req.pipe(upstream);
  });

  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, HOST, () => resolve({
      port: server.address().port,
      close: () => new Promise((done) => server.close(done)),
    }));
  });
}
