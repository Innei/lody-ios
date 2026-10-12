import assert from 'node:assert/strict';
import test from 'node:test';
import {
  htmlFeedbackReport,
  htmlReadError,
  isHTML,
} from '../../src/features/files/htmlPreview.ts';
import { sendPreviewFeedback } from '../../src/features/files/previewFeedback.ts';

function store(initial = []) {
  const listeners = new Set();
  const state = { ready: true, records: initial };
  const writes = [];
  return {
    writes,
    getSnapshot: () => state,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    async put(record) {
      writes.push(record);
      state.records = [record];
    },
    phase(phase) {
      state.records = state.records.map((record) => ({
        ...record,
        send: { ...record.send, phase },
      }));
      listeners.forEach((listener) => listener());
    },
    get listenerCount() {
      return listeners.size;
    },
  };
}
const session = { id: 'original', archived: false };

test('unclassified read errors are not mislabeled as an offline computer or a missing file', () => {
  assert.equal(
    htmlReadError(new Error('Code Collab RPC owner session mismatch')),
    'resource_failed',
  );
  assert.equal(
    htmlReadError(new Error('permission_denied')),
    'permission_denied',
  );
  assert.equal(htmlReadError(new Error('computer offline')), 'offline');
});
const args = (outbox) => ({
  store: outbox,
  session,
  text: 'preview report',
  id: 'report-id',
  connected: true,
  timeoutMs: 100,
});

test('feedback retains original references and resolves to the originating file', () => {
  const issues = [
    {
      reference: '../assets/app.js',
      path: 'assets/app.js',
      code: 'file_not_found',
      kind: 'script',
    },
  ];
  const report = htmlFeedbackReport('docs/index.html', issues);
  assert.deepEqual(JSON.parse(report.slice(report.indexOf('{'))), {
    file: 'docs/index.html',
    issues,
  });
  assert.ok(isHTML('docs/demo.HTM'));
  assert.ok(!isHTML('docs/demo.html.ts'));
});

test('offline feedback is durable in the original outbox and preserves the composer draft', async () => {
  const outbox = store();
  assert.equal(
    await sendPreviewFeedback({ ...args(outbox), connected: false }),
    'queued',
  );
  assert.equal(outbox.writes.length, 1);
  assert.equal(outbox.writes[0].session.id, 'original');
  assert.equal(outbox.writes[0].send.text, 'preview report');
  assert.equal(outbox.writes[0].send.preserveDraft, true);
  assert.equal(outbox.writes[0].send.phase, 'waiting');
});

test('feedback cannot overwrite an existing send or retry', async () => {
  const pending = {
    session,
    send: { id: 'draft', phase: 'failed', text: 'user draft' },
  };
  const outbox = store([pending]);
  await assert.rejects(sendPreviewFeedback(args(outbox)), /pending_send/);
  assert.equal(outbox.writes.length, 0);
  assert.equal(outbox.getSnapshot().records[0], pending);
});

test('feedback is only marked sent on a delivery receipt and releases its subscription', async () => {
  const outbox = store();
  const result = sendPreviewFeedback(args(outbox));
  await Promise.resolve();
  assert.equal(outbox.listenerCount, 1);
  outbox.phase('accepted');
  assert.equal(await result, 'sent');
  assert.equal(outbox.listenerCount, 0);
});

test('uncertain feedback is never replayed or reported as delivered', async () => {
  const outbox = store();
  const result = sendPreviewFeedback(args(outbox));
  await Promise.resolve();
  outbox.phase('unknown');
  assert.equal(await result, 'unknown');
  await assert.rejects(sendPreviewFeedback(args(outbox)), /pending_send/);
  assert.equal(outbox.writes.length, 1);
  assert.equal(outbox.listenerCount, 0);
});

test('a failed delivery stays available in the ordinary conversation for retry', async () => {
  const outbox = store();
  const result = sendPreviewFeedback(args(outbox));
  await Promise.resolve();
  outbox.phase('failed');
  await assert.rejects(result, /send_failed/);
  assert.equal(outbox.getSnapshot().records[0].send.id, 'report-id');
  assert.equal(outbox.listenerCount, 0);
});
