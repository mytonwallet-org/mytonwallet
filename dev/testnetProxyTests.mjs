import assert from 'node:assert/strict';
import http from 'node:http';
import { after, before, describe, it } from 'node:test';

import { startTestnetProxy } from './testnetProxy.mjs';

describe('testnetProxy', () => {
  let upstream;
  let requests;
  let proxy;
  let base;

  before(async () => {
    requests = [];
    upstream = http.createServer((req, res) => {
      const chunks = [];
      req.on('data', (chunk) => chunks.push(chunk));
      req.on('end', () => {
        requests.push({ method: req.method, url: req.url, headers: req.headers, body: Buffer.concat(chunks).toString() });
        res.writeHead(200, { 'content-type': 'application/json', 'access-control-allow-origin': 'https://other' });
        res.end('{"ok":true}');
      });
    });
    await new Promise((resolve) => upstream.listen(0, '127.0.0.1', resolve));
    proxy = await startTestnetProxy({
      port: 0, target: `http://127.0.0.1:${upstream.address().port}`, apiKey: 'test-key',
    });
    base = `http://127.0.0.1:${proxy.port}`;
  });

  after(async () => {
    await proxy.close();
    await new Promise((resolve) => upstream.close(resolve));
  });

  it('answers a CORS preflight itself, allowing the requested headers', async () => {
    const count = requests.length;
    const response = await fetch(`${base}/api/v3/actions`, {
      method: 'OPTIONS',
      headers: { 'access-control-request-headers': 'x-actions-version,x-app-origin' },
    });

    assert.equal(response.status, 204);
    assert.equal(response.headers.get('access-control-allow-origin'), '*');
    assert.equal(response.headers.get('access-control-allow-headers'), 'x-actions-version,x-app-origin');
    assert.equal(requests.length, count);
  });

  it('forwards a request with the key and opens the answer to any origin', async () => {
    const response = await fetch(`${base}/api/v2/sendBoc`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', origin: 'http://localhost', 'x-api-key': 'app-key' },
      body: '{"boc":"te6"}',
    });

    assert.deepEqual(await response.json(), { ok: true });
    assert.equal(response.headers.get('access-control-allow-origin'), '*');
    const request = requests.at(-1);
    assert.equal(request.url, '/api/v2/sendBoc');
    assert.equal(request.body, '{"boc":"te6"}');
    assert.equal(request.headers['x-api-key'], 'test-key');
    assert.equal(request.headers.origin, undefined);
  });

  it('keeps a `//host` path on the target instead of sending the key to that host', async () => {
    const count = requests.length;
    await new Promise((resolve, reject) => {
      http.get({ host: '127.0.0.1', port: proxy.port, path: '//127.0.0.1:1/api' }, (response) => {
        response.resume();
        response.on('end', resolve);
      }).on('error', reject);
    });

    assert.equal(requests.length, count + 1);
    assert.equal(requests.at(-1).url, '//127.0.0.1:1/api');
  });
});

describe('testnetProxy with an upstream that drops mid-answer', () => {
  it('ends the answer instead of leaving the app waiting', async () => {
    const upstream = http.createServer((req, res) => {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.write('{"partial":');
      setTimeout(() => req.socket.destroy(), 50);
    });
    await new Promise((resolve) => upstream.listen(0, '127.0.0.1', resolve));
    const proxy = await startTestnetProxy({ port: 0, target: `http://127.0.0.1:${upstream.address().port}`, apiKey: 'k' });

    const outcome = await fetch(`http://127.0.0.1:${proxy.port}/api`, { signal: AbortSignal.timeout(5000) })
      .then((response) => response.text())
      .then(() => 'ended', (err) => (err.name === 'TimeoutError' ? 'hung' : 'ended'));

    await proxy.close();
    await new Promise((resolve) => upstream.close(resolve));
    assert.equal(outcome, 'ended');
  });
});

describe('testnetProxy with an upstream that redirects', () => {
  it('refuses the redirect instead of passing it to the app', async () => {
    const upstream = http.createServer((req, res) => {
      res.writeHead(307, { location: 'https://example.com/api' });
      res.end();
    });
    await new Promise((resolve) => upstream.listen(0, '127.0.0.1', resolve));
    const proxy = await startTestnetProxy({ port: 0, target: `http://127.0.0.1:${upstream.address().port}`, apiKey: 'k' });

    const response = await fetch(`http://127.0.0.1:${proxy.port}/api`, { method: 'POST', body: '{}', redirect: 'manual' });

    await proxy.close();
    await new Promise((resolve) => upstream.close(resolve));
    assert.equal(response.status, 502);
    assert.equal(response.headers.get('location'), null);
  });
});
