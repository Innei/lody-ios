import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';

async function setup(request) {
  let index = 0;
  const cells = [];
  const effects = [];
  globalThis.__directoryReact = {
    useState(initial) {
      const at = index++;
      if (!(at in cells)) cells[at] = initial;
      return [
        cells[at],
        (next) => {
          cells[at] = next;
        },
      ];
    },
    useEffect(effect, deps) {
      const at = index++;
      if (cells[at] && deps.every((dep, i) => dep === cells[at].deps[i]))
        return;
      const previous = cells[at];
      cells[at] = { deps };
      effects.push(() => {
        previous?.cleanup?.();
        cells[at].cleanup = effect();
      });
    },
  };
  globalThis.__directoryCloud = {
    teamSource: { request },
    parseTeamMembers: (page) => page,
  };
  const bundle = await build({
    entryPoints: [
      new URL('../../src/features/team/useTeamDirectory.ts', import.meta.url)
        .pathname,
    ],
    bundle: true,
    format: 'esm',
    write: false,
    plugins: [
      {
        name: 'directory',
        setup(b) {
          b.onResolve(
            { filter: /^(react|\.\.\/\.\.\/cloud\/team)$/ },
            ({ path }) => ({ path, namespace: 'test' }),
          );
          b.onLoad({ filter: /.*/, namespace: 'test' }, ({ path }) => ({
            contents:
              path === 'react'
                ? 'export const {useEffect,useState}=globalThis.__directoryReact;'
                : 'export const {parseTeamMembers,teamSource}=globalThis.__directoryCloud;',
          }));
        },
      },
    ],
  });
  const { useTeamDirectory } = await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text + `\n// ${Math.random()}`).toString('base64')}`
  );
  return {
    render(scope) {
      index = 0;
      const result = useTeamDirectory(scope);
      effects.splice(0).forEach((effect) => effect());
      return result;
    },
    unmount() {
      cells.forEach((cell) => cell?.cleanup?.());
    },
  };
}

const scope = { userId: 'viewer', workspaceId: 'team', workspaceName: 'Team' };
const tick = () => new Promise((resolve) => setImmediate(resolve));

test('chat resolves all member pages before displaying a multi-member sender directory', async () => {
  const offsets = [];
  const hooks = await setup(async (_, command) => {
    offsets.push(command.args.offset);
    return {
      members: [
        {
          userId: command.args.offset ? 'other' : 'viewer',
          name: command.args.offset ? 'Other' : 'Viewer',
        },
      ],
      total: 2,
    };
  });
  assert.equal(hooks.render(scope).showSenderIdentity, false);
  await tick();
  assert.deepEqual(offsets, [0, 1]);
  assert.deepEqual(hooks.render(scope), {
    senders: { viewer: 'Viewer', other: 'Other' },
    showSenderIdentity: true,
  });
  hooks.unmount();
});

test('a workspace change clears names immediately and drops late responses from the old team', async () => {
  let finish;
  const hooks = await setup((requestScope) => {
    if (requestScope.workspaceId === 'team')
      return new Promise((resolve) => {
        finish = resolve;
      });
    return Promise.resolve({
      members: [{ userId: 'new-viewer', name: 'New' }],
      total: 1,
    });
  });
  hooks.render(scope);
  const next = { ...scope, workspaceId: 'new-team' };
  assert.deepEqual(hooks.render(next), {
    senders: {},
    showSenderIdentity: false,
  });
  finish({ members: [{ userId: 'private-old', name: 'Old' }], total: 2 });
  await tick();
  assert.deepEqual(hooks.render(next), {
    senders: {},
    showSenderIdentity: false,
  });
  hooks.unmount();
});

test('an incomplete directory is never published and signed-out chat makes no member requests', async () => {
  let calls = 0;
  const hooks = await setup(async () => {
    calls++;
    return { members: [], total: 2 };
  });
  hooks.render();
  await tick();
  assert.equal(calls, 0);
  hooks.render(scope);
  await tick();
  assert.deepEqual(hooks.render(scope), {
    senders: {},
    showSenderIdentity: false,
  });
  assert.equal(calls, 1);
  hooks.unmount();
});
