import test from 'node:test';
import assert from 'node:assert/strict';
import { redirectSystemPath } from '../../src/app/+native-intent.ts';
import {
  acknowledgeDeepLink,
  pendingDeepLink,
  subscribeDeepLinks,
} from '../../src/features/notifications/deepLinks.ts';
import {
  parseNotificationRoute,
  routeFromDeepLink,
  resolveNotificationClick,
} from '../../src/features/notifications/routing.ts';
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
test('a workspace without a slug still resolves from its id in the link', () => {
  const context2 = {
    ...context,
    workspaces: [{ id: 'workspace', slug: null }],
  };
  assert.deepEqual(
    resolveNotificationClick(
      { ...click, route: '/workspace/sessions/session' },
      context2,
    ),
    { kind: 'session', session },
  );
  assert.equal(resolveNotificationClick(click, context2).kind, 'discard');
});
test('widget and notification links share the route space, ignoring foreign schemes', () => {
  assert.equal(routeFromDeepLink('lody:///ws/sessions/s1'), '/ws/sessions/s1');
  assert.equal(routeFromDeepLink('lody://ws/sessions/s1'), '/ws/sessions/s1');
  assert.equal(
    routeFromDeepLink('lody:///ws/sessions/s1?from=widget#top'),
    '/ws/sessions/s1',
  );
  assert.deepEqual(
    parseNotificationRoute(routeFromDeepLink('lody:///my%20ws/sessions/s%2B1')),
    { workspaceSlug: 'my ws', sessionId: 's+1' },
  );
  for (const url of [
    'https://lody.ai/ws/sessions/s1',
    'lody-ios:///ws/sessions/s1',
    'ody:///ws/sessions/s1',
    '/ws/sessions/s1',
  ])
    assert.equal(routeFromDeepLink(url), null);
});

test('native session links survive cold startup and have one navigation owner on every open', () => {
  const path = 'lody:///work/sessions/session';
  assert.equal(redirectSystemPath({ path, initial: true }), '/');
  const cold = pendingDeepLink();
  assert.equal(cold.route, '/work/sessions/session');
  assert.equal(
    resolveNotificationClick({ ...cold, userId: 'user' }, context).kind,
    'session',
  );

  let changes = 0;
  const stop = subscribeDeepLinks(() => changes++);
  acknowledgeDeepLink(cold.id);
  assert.equal(pendingDeepLink(), null);
  // A warm link must not cause Expo Router to push either NotFound or Home.
  assert.equal(redirectSystemPath({ path, initial: false }), null);
  const warm = pendingDeepLink();
  assert.notEqual(warm.id, cold.id);
  acknowledgeDeepLink(cold.id);
  assert.equal(
    pendingDeepLink(),
    warm,
    'An old acknowledgement must not erase a new click',
  );
  acknowledgeDeepLink(warm.id);
  assert.equal(changes, 3);
  stop();

  for (const other of [
    'lody:///debug',
    'https://example.com/work/sessions/session',
    'lody:///work/sessions/%2fother',
  ]) {
    assert.equal(redirectSystemPath({ path: other, initial: false }), other);
    assert.equal(pendingDeepLink(), null);
  }
  assert.equal(
    redirectSystemPath({ path: '/work/sessions/session', initial: false }),
    null,
  );
  acknowledgeDeepLink(pendingDeepLink().id);
  assert.equal(changes, 3, 'Unmounted subscribers must not receive URL events');
});
