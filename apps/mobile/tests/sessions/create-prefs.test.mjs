import assert from 'node:assert/strict';
import { effortsFor } from '../../src/cloud/send/capability.ts';
import test from 'node:test';
import {
  CHAT_PREFS_KEY,
  rememberedContext,
  rememberedProject,
  rememberedModelChoice,
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

test('remembers chat context without overwriting the last project', () => {
  const project = withSelection(null, 'p1', {
    machineId: 'm1',
    agentKey: 'm1:c1',
  });
  const chat = withSelection(
    project,
    CHAT_PREFS_KEY,
    { machineId: 'm2', agentKey: 'm2:c2' },
    'chat',
  );
  assert.equal(rememberedContext(chat), 'chat');
  assert.equal(chat.projectId, 'p1');
  assert.equal(
    restoreSelection(chat, CHAT_PREFS_KEY, options).agentKey,
    'm2:c2',
  );
});

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
    choice: { modelId: undefined, effort: undefined, modeId: undefined },
  });
  assert.deepEqual(restoreSelection(null, 'p1', options), {
    machineId: 'm1',
    agentKey: 'm1:c1',
    choice: { modelId: undefined, effort: undefined, modeId: undefined },
  });
  assert.equal(restoreSelection(prefs, 'other', options).agentKey, 'm1:c1');
});

test('remembers each model across projects and serialization, without leaking agent choices', () => {
  const capability = {
    ...options.capabilities[0],
    models: [{ id: 'opus' }, { id: 'sonnet' }],
    modes: [{ id: 'plan' }, { id: 'bypassPermissions' }],
    reasoningEfforts: { opus: ['low', 'high'], sonnet: ['low', 'high'] },
  };
  let prefs = withSelection(null, 'p1', {
    agentKey: 'm2:c2',
    modelId: 'opus',
    effort: 'high',
    modeId: 'plan',
  });
  assert.deepEqual(
    rememberedModelChoice(prefs, 'm2:c2', capability, 'sonnet'),
    {
      modelId: 'sonnet',
      effort: undefined,
      modeId: 'bypassPermissions',
    },
  );
  prefs = withSelection(prefs, 'p2', {
    agentKey: 'm2:c2',
    modelId: 'sonnet',
    effort: 'low',
    modeId: 'bypassPermissions',
  });
  prefs = JSON.parse(JSON.stringify(prefs));
  assert.deepEqual(rememberedModelChoice(prefs, 'm2:c2', capability, 'opus'), {
    modelId: 'opus',
    effort: 'high',
    modeId: 'plan',
  });
  assert.equal(
    rememberedModelChoice(prefs, 'another-agent', capability, 'opus').modeId,
    'bypassPermissions',
  );
  assert.equal(
    rememberedModelChoice(prefs, 'another-agent', capability, 'opus').effort,
    undefined,
  );
  const removed = {
    ...capability,
    reasoningEfforts: {},
    modes: [{ id: 'bypassPermissions' }],
  };
  assert.deepEqual(rememberedModelChoice(prefs, 'm2:c2', removed, 'opus'), {
    modelId: 'opus',
    effort: undefined,
    modeId: 'bypassPermissions',
  });
  prefs = withSelection(prefs, 'p1', { agentKey: 'm2:c2', modelId: 'opus' });
  assert.equal(
    rememberedModelChoice(
      JSON.parse(JSON.stringify(prefs)),
      'm2:c2',
      capability,
      'opus',
    ).modeId,
    undefined,
    'explicit assistant default is remembered',
  );
});

test('full access defaults only use modes the assistant actually offers', () => {
  for (const id of [
    'agent-full-access',
    'danger-full-access',
    'bypassPermissions',
    'yolo',
    'always-approve',
  ]) {
    const capability = {
      ...options.capabilities[0],
      modes: [{ id: 'plan' }, { id }],
    };
    assert.equal(rememberedModelChoice(null, 'agent', capability).modeId, id);
  }
  assert.equal(
    rememberedModelChoice(null, 'agent', options.capabilities[0]).modeId,
    undefined,
  );
  const legacy = {
    projects: {
      p1: {
        agentKey: 'm2:c2',
        modelId: 'opus',
        effort: 'high',
        modeId: 'plan',
      },
    },
  };
  assert.equal(restoreSelection(legacy, 'p1', options).choice.modeId, 'plan');
});

test('independent permission, boolean and custom choices survive serialization and stay scoped to the agent and model', () => {
  const select = (id, values, category = id) => ({
    id,
    name: id,
    type: 'select',
    category,
    options: values.map((id) => ({ id, name: id })),
  });
  const capability = {
    ...options.capabilities[0],
    reasoningEfforts: {},
    configOptions: [
      select('permission_mode', ['ask', 'always-approve'], '_permission'),
      { id: 'fast', type: 'boolean', options: [] },
      select('agent_preset', ['standard', 'coder']),
      select('effort', ['low', 'high'], 'thought_level'),
    ],
  };
  const values = {
    permission_mode: 'always-approve',
    fast: false,
    agent_preset: 'coder',
  };
  let prefs = withSelection(null, 'p1', {
    agentKey: 'grok',
    modelId: 'a',
    effort: 'high',
    configOptionValues: values,
  });
  prefs = withSelection(prefs, 'p2', {
    agentKey: 'grok',
    modelId: 'b',
    configOptionValues: { permission_mode: 'ask' },
  });
  prefs = JSON.parse(JSON.stringify(prefs));
  assert.deepEqual(
    rememberedModelChoice(prefs, 'grok', capability, 'a').configOptionValues,
    values,
  );
  assert.equal(
    rememberedModelChoice(prefs, 'grok', capability, 'a').effort,
    'high',
  );
  assert.deepEqual(
    effortsFor(capability, 'a'),
    ['low', 'high'],
    'config-only effort reaches both native hosts',
  );
  assert.equal(
    rememberedModelChoice(prefs, 'other-agent', capability, 'a')
      .configOptionValues,
    undefined,
  );
  assert.equal(
    rememberedModelChoice(prefs, 'grok', capability, 'c').configOptionValues,
    undefined,
  );
  const changed = {
    ...capability,
    configOptions: [
      select('permission_mode', ['ask']),
      select('fast', ['on', 'off']),
    ],
  };
  assert.equal(
    rememberedModelChoice(prefs, 'grok', changed, 'a').configOptionValues,
    undefined,
    'removed values and changed option types are discarded',
  );
  prefs = withSelection(prefs, 'p1', {
    agentKey: 'grok',
    modelId: 'a',
    configOptionValues: {},
  });
  assert.equal(
    rememberedModelChoice(
      JSON.parse(JSON.stringify(prefs)),
      'grok',
      capability,
      'a',
    ).configOptionValues,
    undefined,
    'Use default clears the remembered override',
  );
});
