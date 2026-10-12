import assert from 'node:assert/strict';
import test from 'node:test';
import {
  requestOpenSession,
  requestOpenSessionFromPage,
  requestShareSession,
  subscribeSessionNav,
} from '../../src/features/sessions/sessionNav.ts';

const session = {
  id: 's1',
  machineId: 'm',
  title: 'T',
  status: 'idle',
  archived: false,
  pinned: false,
  projectId: 'p',
  createdAt: '2026-01-01',
};

test('a fork pushes through the current navigation owner while its source page is still open', async () => {
  const stack = [];
  let closeSource;
  let closeFork;
  const stop = subscribeSessionNav(async (intent) => {
    stack.push(intent.session.id);
    await new Promise((resolve) => {
      if (intent.kind === 'open-from-page') closeFork = resolve;
      else closeSource = resolve;
    });
    stack.pop();
  });
  const source = requestOpenSession(session);
  const fork = requestOpenSessionFromPage('workspace', 'viewer', {
    ...session,
    id: 'fork',
  });
  assert.deepEqual(stack, ['s1', 'fork']);
  closeFork();
  await fork;
  assert.deepEqual(
    stack,
    ['s1'],
    'Back from the fork preserves its source page',
  );
  closeSource();
  await source;
  assert.deepEqual(stack, []);
  stop();
});

test('leaving the navigation scope settles a pending fork and blocks its late completion', async () => {
  let release;
  const opened = [];
  const pendingPage = new Promise((resolve) => {
    release = resolve;
  });
  const stop = subscribeSessionNav(async (intent, signal) => {
    await pendingPage;
    if (!signal.aborted) opened.push(intent.session.id);
  });
  const fork = requestOpenSessionFromPage(
    'old-workspace',
    'old-viewer',
    session,
  );
  stop();
  await fork;
  release();
  await Promise.resolve();
  assert.deepEqual(opened, []);
});

test('sharing can open while the same navigation owner awaits a session page', async () => {
  let release;
  const page = new Promise((resolve) => {
    release = resolve;
  });
  const seen = [];
  const stop = subscribeSessionNav(async (intent) => {
    seen.push(intent.kind);
    if (intent.kind === 'open') await page;
  });
  const open = requestOpenSession(session);
  await requestShareSession('workspace', session.id);
  assert.deepEqual(seen, ['open', 'share']);
  release();
  await open;
  stop();
});

test('requestOpenSession waits for the subscriber and preserves order', async () => {
  const seen = [];
  const stop = subscribeSessionNav(async (intent) => {
    seen.push(intent.kind);
  });
  await requestOpenSession(session);
  assert.deepEqual(seen, ['open']);
  stop();
});

test('intents queue until a subscriber attaches', async () => {
  const seen = [];
  const pending = requestOpenSession(session);
  const stop = subscribeSessionNav(async (intent) => {
    seen.push(intent.kind);
  });
  await pending;
  assert.deepEqual(seen, ['open']);
  stop();
});

test('handler throw is swallowed by requestOpenSession', async () => {
  const stop = subscribeSessionNav(async () => {
    throw new Error('boom');
  });
  await requestOpenSession(session);
  stop();
});

test('the latest subscriber owns navigation until it unmounts', async () => {
  const seen = [];
  const stopRoot = subscribeSessionNav(async () => seen.push('root'));
  const stopPad = subscribeSessionNav(async () => seen.push('pad'));

  await requestOpenSession(session);
  stopPad();
  await requestOpenSession(session);

  assert.deepEqual(seen, ['pad', 'root']);
  stopRoot();
});

test('a pending presentation keeps later intents in order', async () => {
  const seen = [];
  let release;
  const gate = new Promise((resolve) => {
    release = resolve;
  });
  const stop = subscribeSessionNav(async (intent) => {
    seen.push(intent.session.title);
    if (intent.session.title === 'First') await gate;
  });
  const first = requestOpenSession({ ...session, title: 'First' });
  const second = requestOpenSession({ ...session, title: 'Second' });

  await Promise.resolve();
  assert.deepEqual(seen, ['First']);
  release();
  await Promise.all([first, second]);

  assert.deepEqual(seen, ['First', 'Second']);
  stop();
});

test('leaving a workspace aborts its pending navigation before a new owner handles requests', async () => {
  const opened = [];
  let release;
  let oldSignal;
  const creation = new Promise((resolve) => {
    release = resolve;
  });
  const stopOld = subscribeSessionNav(async (intent, signal) => {
    oldSignal = signal;
    await creation;
    if (!signal.aborted) opened.push(intent.session.id);
  });
  const oldRequest = requestOpenSession(session);
  assert.equal(oldSignal.aborted, false);
  stopOld();
  assert.equal(oldSignal.aborted, true);
  const stopNew = subscribeSessionNav(async (intent, signal) => {
    assert.equal(signal.aborted, false);
    opened.push(intent.session.id);
  });
  const newRequest = requestOpenSession({
    ...session,
    id: 'new-workspace-session',
  });
  await Promise.all([oldRequest, newRequest]);
  assert.deepEqual(opened, ['new-workspace-session']);
  release();
  await Promise.resolve();
  assert.deepEqual(opened, ['new-workspace-session']);
  stopNew();
});
