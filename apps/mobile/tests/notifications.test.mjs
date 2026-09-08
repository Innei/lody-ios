import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parseNotificationRoute,
  resolveNotificationClick,
} from '../src/features/notifications/routing.ts';
const click = { id: 'notice', route: '/work/sessions/session', userId: 'user' };
const session = { id: 'session', title: 'Synthetic' };
const context = {
  ready: true,
  userId: 'user',
  workspaces: [{ id: 'workspace', slug: 'work' }],
  selectedId: 'workspace',
  loading: false,
  connected: true,
  sessions: [session],
};
test('notification links accept legacy routes and reject malformed or external destinations', () => {
  assert.deepEqual(parseNotificationRoute('/work/sessions/session'), {
    workspaceSlug: 'work',
    sessionId: 'session',
  });
  for (const route of [
    'https://lody.ai/work/sessions/id',
    '//evil/sessions/id',
    '/work/sessions/%2fother',
    '/work/sessions/%ZZ',
    '/work/sessions/..',
    '/work/sessions/id?x=1',
    '/work/sessions/id/extra',
  ])
    assert.equal(parseNotificationRoute(route), null);
});
test('cold clicks wait for auth, switch to a member workspace, then open the actual catalog session', () => {
  assert.equal(
    resolveNotificationClick(click, { ...context, ready: false }).kind,
    'wait',
  );
  assert.deepEqual(
    resolveNotificationClick(click, { ...context, selectedId: 'other' }),
    { kind: 'workspace', id: 'workspace' },
  );
  assert.equal(
    resolveNotificationClick(click, { ...context, sessions: [], loading: true })
      .kind,
    'wait',
  );
  assert.deepEqual(resolveNotificationClick(click, context), {
    kind: 'session',
    session,
  });
});
test('account changes and membership removal never open a stale notification', () => {
  assert.equal(
    resolveNotificationClick(click, { ...context, userId: 'other' }).kind,
    'discard',
  );
  assert.equal(
    resolveNotificationClick(click, { ...context, userId: undefined }).kind,
    'discard',
  );
  assert.equal(
    resolveNotificationClick(click, { ...context, workspaces: [] }).kind,
    'discard',
  );
  assert.equal(
    resolveNotificationClick(click, { ...context, sessions: [] }).kind,
    'discard',
  );
  assert.equal(
    resolveNotificationClick(click, {
      ...context,
      sessions: [],
      connected: false,
    }).kind,
    'wait',
  );
});
