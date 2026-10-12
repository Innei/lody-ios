import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import {
  selectedRoleChoice,
  detachChangedRole,
} from '../../src/features/sessions/runOptions.ts';
import { pendingSessionFromDraft } from '../../src/features/sessions/createDraft.ts';

const role = {
  id: 'reviewer',
  name: 'Reviewer',
  machineId: 'm1',
  agentConfigId: 'a1',
  agentName: 'Codex',
  available: true,
  revision: 2,
  runConfig: {
    modelId: 'a',
    modeId: 'read-only',
    configOptionValues: { effort: 'high', fast: false },
  },
};
const capability = { reasoningEffortConfigId: 'effort' };

test('Role applies pinned fields, explicit None retains values, and changing pinned effort or mode detaches', () => {
  const picked = selectedRoleChoice(
    { modelId: 'b', mcpServerIds: ['docs'] },
    role,
    capability,
  );
  assert.equal(picked.modelId, 'a');
  assert.equal(picked.modeId, 'read-only');
  assert.equal(picked.effort, 'high');
  assert.equal(picked.configOptionValues.fast, false);
  assert.deepEqual(picked.mcpServerIds, ['docs']);
  assert.equal(selectedRoleChoice(picked, null).modelId, 'a');
  assert.equal(selectedRoleChoice(picked, null).frozenRole, undefined);
  assert.equal(
    detachChangedRole({ ...picked, effort: 'low' }, capability).agentRoleId,
    null,
  );
  assert.equal(
    detachChangedRole({ ...picked, modeId: 'full' }, capability).agentRoleId,
    null,
  );
  assert.equal(
    detachChangedRole({ ...picked, mcpServerIds: [] }, capability).agentRoleId,
    'reviewer',
  );
  const inherited = {
    modelId: 'a',
    agentRoleId: 'reviewer',
    agentRoleRevision: 2,
  };
  assert.equal(
    detachChangedRole(inherited, capability, inherited).agentRoleId,
    'reviewer',
  );
  assert.equal(
    detachChangedRole({ ...inherited, modelId: 'b' }, capability, inherited)
      .agentRoleId,
    null,
  );
});

test('native create selections enter both the durable creation target and frozen first-turn choice', () => {
  const choice = selectedRoleChoice({ mcpServerIds: [] }, role, capability);
  const { record, created } = pendingSessionFromDraft(
    {
      sessionId: 's',
      userId: 'u',
      workspaceId: 'w',
      projectId: 'm1:local:p',
      projectName: 'Project',
      useWorktree: true,
      agent: {
        id: 'a1',
        name: 'Codex',
        machineId: 'm1',
        machineName: 'Mac',
        cliType: 'builtin',
        agentType: 'codex',
      },
      choice,
    },
    { id: 'turn', text: 'Task', startedAt: 1, attachments: [] },
  );
  const creation = JSON.parse(record.send.creation);
  assert.equal(creation.useWorktree, true);
  assert.equal(creation.agentRoleId, 'reviewer');
  assert.equal(creation.agentRoleRevision, 2);
  assert.deepEqual(record.send.choice.frozenRole, role.runConfig);
  assert.deepEqual(record.send.choice.mcpServerIds, []);
  assert.equal(created.agentRoleId, 'reviewer');
});

async function composerHook(request) {
  let index = 0;
  const cells = [];
  const effects = [];
  globalThis.__runOptionsHooks = {
    useState(initial) {
      const at = index++;
      if (!(at in cells)) cells[at] = initial;
      return [
        cells[at],
        (next) => {
          cells[at] = typeof next === 'function' ? next(cells[at]) : next;
        },
      ];
    },
    useReducer(reducer, initial) {
      const at = index++;
      if (!(at in cells)) {
        cells[at] = {
          value: initial,
          dispatch: (action) => {
            cells[at].value = reducer(cells[at].value, action);
          },
        };
      }
      return [cells[at].value, cells[at].dispatch];
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
    runOptions: request,
  };
  const bundle = await build({
    entryPoints: [
      new URL(
        '../../src/hooks/screens/useComposerRunOptions.ts',
        import.meta.url,
      ).pathname,
    ],
    bundle: true,
    format: 'esm',
    write: false,
    plugins: [
      {
        name: 'run-options-hooks',
        setup(builder) {
          builder.onResolve(
            { filter: /^(react|@lody-ios\/kit)$/ },
            ({ path }) => ({
              path,
              namespace: 'fixture',
            }),
          );
          builder.onLoad(
            { filter: /.*/, namespace: 'fixture' },
            ({ path }) => ({
              contents:
                path === 'react'
                  ? 'export const {useEffect,useReducer,useState}=globalThis.__runOptionsHooks;'
                  : 'export const {runOptions}=globalThis.__runOptionsHooks;',
            }),
          );
        },
      },
    ],
  });
  const { useComposerRunOptions } = await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text + `\n// ${Math.random()}`).toString('base64')}`
  );
  return {
    render(source) {
      index = 0;
      const result = useComposerRunOptions(source);
      effects.splice(0).forEach((effect) => effect());
      return result;
    },
    unmount() {
      cells.forEach((cell) => cell?.cleanup?.());
    },
  };
}

const nextTick = () => new Promise((resolve) => setImmediate(resolve));
const source = { workspaceId: 'w', userId: 'u', sessionId: 's' };

test('unavailable chat run options expose a retryable failure and a retry replaces the incomplete catalog', async () => {
  let attempts = 0;
  const catalog = { roles: [role], mcpServers: [] };
  const hook = await composerHook(async () => {
    if (++attempts === 1) throw new Error('workspace stream unavailable');
    return JSON.stringify(catalog);
  });
  hook.render(source);
  await nextTick();
  const failed = hook.render(source);
  assert.equal(failed.error, 'run-options-unavailable');
  assert.equal(failed.catalog.unavailable, true);
  failed.refresh();
  hook.render(source);
  assert.equal(hook.render(source).loading, true);
  await nextTick();
  assert.deepEqual(hook.render(source).catalog, catalog);
  assert.equal(hook.render(source).error, '');
  assert.equal(attempts, 2);
  hook.unmount();
});

test('workspace changes discard late run-option responses and signing out makes no request', async () => {
  let finishPrevious;
  let attempts = 0;
  const hook = await composerHook((json) => {
    attempts++;
    if (JSON.parse(json).workspaceId === 'w')
      return new Promise((resolve) => {
        finishPrevious = resolve;
      });
    return Promise.resolve(
      JSON.stringify({ roles: [], mcpServers: [{ id: 'new', name: 'New' }] }),
    );
  });
  hook.render(source);
  const nextSource = { ...source, workspaceId: 'new-workspace' };
  assert.deepEqual(hook.render(nextSource).catalog.roles, []);
  finishPrevious(JSON.stringify({ roles: [role], mcpServers: [] }));
  await nextTick();
  const current = hook.render(nextSource);
  assert.deepEqual(current.catalog.roles, []);
  assert.equal(current.catalog.mcpServers[0].id, 'new');
  hook.render();
  await nextTick();
  assert.deepEqual(hook.render().catalog, { roles: [], mcpServers: [] });
  assert.equal(attempts, 2);
  hook.unmount();
});
