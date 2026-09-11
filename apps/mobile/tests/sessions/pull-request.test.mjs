import assert from 'node:assert/strict';
import test from 'node:test';
import { pullRequestReferences } from '../../src/features/pull-request/references.ts';
import { createPullRequestSource } from '../../src/features/pull-request/source.ts';
import { checksSummary } from '../../src/features/pull-request/checks.ts';

test('CI summary distinguishes empty, incomplete, denied, running and passing', () => {
  const data = { checks: [] };
  assert.equal(checksSummary(data), 'empty');
  assert.equal(
    checksSummary({ ...data, checksError: 'forbidden' }),
    'unavailable',
  );
  assert.equal(checksSummary({ ...data, checksTruncated: true }), 'partial');
  assert.equal(
    checksSummary({ checks: [{ status: 'queued', conclusion: null }] }),
    'active',
  );
  assert.equal(
    checksSummary({ checks: [{ status: 'completed', conclusion: 'success' }] }),
    'passed',
  );
  assert.equal(
    checksSummary({ checks: [{ status: 'completed', conclusion: 'failure' }] }),
    'failed',
  );
  assert.equal(
    checksSummary({ checks: [{ status: 'completed', conclusion: null }] }),
    'finished',
  );
});

test('PR associations use OSS URL/status and separate CI rollups; invalid targets never become requests', () => {
  const url = 'https://github.com/LodyAI/Lody/pull/31';
  const refs = pullRequestReferences(
    [
      { url, status: 'open', number: 999, repository: 'attacker/repo' },
      { url, status: 'draft' },
      { url: 'https://evil.example/LodyAI/Lody/pull/1', status: 'open' },
      { url: 'https://github.com/LodyAI/../pull/1', status: 'open' },
      { url: `${url}?token=secret`, status: 'open' },
      { url: 'https://github.com/LodyAI/Lody/pull/32', status: 'merged' },
    ],
    { [url]: { s: 'f', t: 1 } },
  );
  assert.equal(refs.length, 2);
  assert.deepEqual(refs[0], {
    url,
    status: 'open',
    number: 31,
    repository: 'LodyAI/Lody',
    ci: 'f',
  });
  assert.equal(refs[1].status, 'merged');
});

test('PR refresh shares requests, retains labeled stale content, and does not publish after disposal', async () => {
  let resolve;
  let calls = 0;
  const source = createPullRequestSource(
    () => {
      calls++;
      return new Promise((r) => {
        resolve = r;
      });
    },
    async () => {},
  );
  const first = source.refresh();
  const second = source.refresh();
  assert.equal(first, second);
  assert.equal(calls, 1);
  resolve({ headSha: 'old', checks: [{ id: 1 }] });
  await first;
  const pending = source.refresh();
  source.dispose();
  resolve({ headSha: 'new', checks: [{ id: 2 }] });
  await pending;
  assert.equal(source.getSnapshot().data, undefined);
  assert.equal(source.getSnapshot().error, 'unauthorized');
});

test('a failed refresh is distinct from an empty PR; comments are never automatically retried', async () => {
  let writes = 0;
  const initial = { headSha: 'old', checks: [] };
  const source = createPullRequestSource(
    async () => {
      throw new Error('forbidden');
    },
    async () => {
      writes++;
      throw new Error('comment_unknown');
    },
    initial,
  );
  await source.refresh();
  assert.equal(source.getSnapshot().data, initial);
  assert.equal(source.getSnapshot().error, 'forbidden');
  await assert.rejects(source.postComment('hello'), /comment_unknown/);
  assert.equal(writes, 1);
});

test('a confirmed comment stays successful when the subsequent refresh fails', async () => {
  let writes = 0;
  const source = createPullRequestSource(
    async () => {
      throw new Error('unavailable');
    },
    async () => {
      writes++;
    },
  );
  await source.postComment('hello');
  await source.refresh();
  assert.equal(writes, 1);
  assert.equal(source.getSnapshot().error, 'unavailable');
});
