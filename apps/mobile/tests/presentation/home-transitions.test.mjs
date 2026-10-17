import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  extractCompactStack,
  insertSessionRoute,
} from '../../src/lib/presentation/homeTransitions.ts';

const session = { id: 'session', panel: false };
const diff = { id: 'file-diff', panel: true };
const content = { id: 'file-content', panel: true };
const simulator = { id: 'simulator', panel: false };
const settings = { id: 'settings', panel: false };
const presented = {
  1: {
    page: session,
    params: { session: 's1' },
    presentation: { style: 'push' },
  },
  2: { page: diff, params: { path: 'a.ts' }, presentation: { style: 'push' } },
  3: {
    page: content,
    params: { path: 'a.ts' },
    presentation: { style: 'formSheet' },
  },
  4: {
    page: settings,
    params: undefined,
    presentation: { style: 'pageSheet' },
  },
  5: { page: simulator, params: {}, presentation: { style: 'push' } },
};
const route = (id) => ({
  key: `presented-${id}`,
  name: 'presented/[presentationId]',
  params: { presentationId: String(id) },
});
const index = { key: 'index-1', name: 'index' };
const lookup = (value) =>
  value.name === 'presented/[presentationId]'
    ? presented[value.params.presentationId]
    : undefined;

test('unfolding moves the pushed session and the panel pages pushed after it out of the router', () => {
  const result = extractCompactStack(
    [index, route(1), route(2), route(4)],
    lookup,
    'session',
  );
  assert.deepEqual(result.session, { session: 's1' });
  assert.deepEqual(
    result.panel.map((entry) => entry.page.id),
    ['file-diff'],
  );
  assert.deepEqual(
    result.routes.map((value) => value.key),
    ['index-1', 'presented-4'],
  );
});

test('open sheets stay where they are, even panel pages presented as sheets', () => {
  const result = extractCompactStack(
    [index, route(1), route(3)],
    lookup,
    'session',
  );
  assert.deepEqual(result.panel, []);
  assert.deepEqual(
    result.routes.map((value) => value.key),
    ['index-1', 'presented-3'],
  );
});

test('a project list pushed in the phone stack returns to the list root', () => {
  const result = extractCompactStack(
    [
      index,
      {
        key: 'project-1',
        name: 'project/[projectId]',
        params: { projectId: 'p' },
      },
      route(1),
    ],
    lookup,
    'session',
  );
  assert.deepEqual(result.session, { session: 's1' });
  assert.deepEqual(
    result.routes.map((value) => value.key),
    ['index-1'],
  );
});

test('pages that are not panel content stay pushed', () => {
  const result = extractCompactStack(
    [index, route(1), route(5)],
    lookup,
    'session',
  );
  assert.deepEqual(result.panel, []);
  assert.deepEqual(
    result.routes.map((value) => value.key),
    ['index-1', 'presented-5'],
  );
});

test('nothing changes without a pushed session', () => {
  const routes = [index, route(4)];
  const result = extractCompactStack(routes, lookup, 'session');
  assert.equal(result.session, undefined);
  assert.equal(result.routes, routes);
});

test('folding pushes the session directly above the list, beneath open sheets', () => {
  const routes = insertSessionRoute([index, route(4)], 9);
  assert.deepEqual(
    routes.map((value) => value.key),
    ['index-1', 'presented-9', 'presented-4'],
  );
  assert.deepEqual(routes[1].params, { presentationId: '9' });
  assert.equal(routes[1].name, 'presented/[presentationId]');
});

test('a project list without an open session also returns to the list root', () => {
  const result = extractCompactStack(
    [
      index,
      {
        key: 'project-1',
        name: 'project/[projectId]',
        params: { projectId: 'p' },
      },
      route(4),
    ],
    lookup,
    'session',
  );
  assert.equal(result.session, undefined);
  assert.deepEqual(
    result.routes.map((value) => value.key),
    ['index-1', 'presented-4'],
  );
});
