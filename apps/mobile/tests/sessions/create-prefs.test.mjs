import assert from 'node:assert/strict';
import test from 'node:test';
import {
  rememberedProject,
  restoreSelection,
  withSelection,
} from '../../src/features/sessions/createPrefs.ts';

const options = {
  sessionId: 's',
  project: { id: 'p1', name: 'P' },
  agents: [
    {
      id: 'c1',
      name: 'A',
      machineId: 'm1',
      machineName: 'Mac',
      cliType: 'builtin',
      agentType: 'codex',
    },
    {
      id: 'c2',
      name: 'B',
      machineId: 'm2',
      machineName: 'PC',
      cliType: 'builtin',
      agentType: 'claude',
    },
  ],
  capabilities: [
    {
      machineId: 'm2',
      cliType: 'builtin',
      agentType: 'claude',
      models: [{ id: 'opus', name: 'Opus' }],
      modes: [{ id: 'plan', name: 'Plan' }],
      reasoningEfforts: { opus: ['low', 'high'] },
    },
  ],
};

test('restores the remembered agent and model per project, dropping choices the machine no longer offers', () => {
  const prefs = withSelection({ projectId: 'old' }, 'p1', {
    machineId: 'm2',
    agentKey: 'm2:c2',
    modelId: 'opus',
    effort: 'high',
    modeId: 'plan',
  });
  assert.equal(prefs.projectId, 'p1');
  assert.equal(rememberedProject(prefs, [{ id: 'p1', name: 'P' }]), 'p1');
  assert.equal(
    rememberedProject(prefs, [{ id: 'p9', name: 'Gone' }]),
    undefined,
  );
  assert.deepEqual(restoreSelection(prefs, 'p1', options), {
    machineId: 'm2',
    agentKey: 'm2:c2',
    choice: { modelId: 'opus', effort: 'high', modeId: 'plan' },
  });
  const stale = withSelection(prefs, 'p1', {
    machineId: 'm2',
    agentKey: 'm2:removed',
    modelId: 'gone',
    effort: 'high',
    modeId: 'plan',
  });
  assert.deepEqual(restoreSelection(stale, 'p1', options), {
    machineId: 'm2',
    agentKey: 'm2:c2',
    choice: { modelId: undefined, effort: undefined, modeId: 'plan' },
  });
  assert.deepEqual(restoreSelection(null, 'p1', options), {
    machineId: 'm1',
    agentKey: 'm1:c1',
    choice: { modelId: undefined, effort: undefined, modeId: undefined },
  });
  assert.equal(restoreSelection(prefs, 'other', options).agentKey, 'm1:c1');
});
