import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import test from 'node:test';
import diagnose from '../../verification/ui/metro-diagnostics.cjs';

test('Metro diagnostics preserve HEAD/GET responses and identify aborted requests without secrets', async () => {
  const entries = [];
  const server = http.createServer(
    diagnose(
      (req, res) => {
        if (req.headers['x-stall']) return;
        res.end('ready');
      },
      (line) => entries.push(JSON.parse(line)),
    ),
  );
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}`;
  try {
    for (const method of ['HEAD', 'GET']) {
      const response = await fetch(`${url}/?token=secret`, {
        method,
        headers: { authorization: 'secret' },
      });
      assert.equal(response.status, 200);
      assert.equal(await response.text(), method === 'HEAD' ? '' : 'ready');
    }
    const controller = new AbortController();
    const closed = new Promise((resolve) =>
      server.once('request', (_req, res) => {
        res.once('close', resolve);
        controller.abort();
      }),
    );
    await assert.rejects(
      fetch(`${url}/status`, {
        headers: { 'x-stall': '1' },
        signal: controller.signal,
      }),
    );
    await closed;
    assert.equal(entries.filter((e) => e.metroRequest === 'start').length, 3);
    assert.deepEqual(
      entries.filter((e) => e.metroRequest === 'end').map((e) => e.finished),
      [true, true, false],
    );
    assert.ok(entries.every((e) => e.path === '/' || e.path === '/status'));
    assert.ok(!JSON.stringify(entries).includes('secret'));
    const before = entries.length;
    await (await fetch(`${url}/index.bundle`)).text();
    assert.equal(entries.length, before);
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
});
