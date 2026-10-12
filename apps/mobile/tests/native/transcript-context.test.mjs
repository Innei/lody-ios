import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { LoroDoc } from 'loro-crdt/base64';
import {
  projectAgentUsage,
  legacyAgentQuotas,
  mergeAgentQuotas,
  selectSessionQuotas,
} from '../../../../packages/cloud-runtime/src/protocol/agent-usage.ts';

const bundle = await build({
  entryPoints: ['packages/cloud-runtime/src/runtime/project.ts'],
  bundle: true,
  platform: 'node',
  format: 'esm',
  write: false,
});
const { projectSession } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);

test('goal lifecycle prefers the latest history snapshot, sanitizes private tails and records clear', () => {
  const doc = new LoroDoc();
  const history = doc.getList('history');
  const goal = {
    type: 'goal',
    threadId: 'thread',
    objective: 'Finish the repair',
    status: 'active',
    tokensUsed: 42,
  };
  history.push({ id: 'first', role: 'assistant', items: [goal] });
  history.push({
    id: 'second',
    role: 'assistant',
    items: [
      {
        ...goal,
        status: 'paused',
        objective:
          'Finish the repair\nThe "lody" MCP server provides tools for this conversation:\nprivate-tail',
        tokenBudget: 1000,
        secret: 'hidden',
      },
    ],
  });
  doc.commit();
  const paused = projectSession(doc, 'live');
  assert.equal(paused.goal.status, 'paused');
  assert.equal(paused.goal.objective, 'Finish the repair');
  assert.equal(paused.goal.tokenBudget, 1000);
  assert.ok(!JSON.stringify(paused).includes('private-tail'));
  assert.ok(!JSON.stringify(paused).includes('hidden'));
  history.push({
    id: 'cleared',
    role: 'assistant',
    items: [{ ...goal, status: 'cleared', tokensUsed: undefined }],
  });
  doc.commit();
  assert.equal(projectSession(doc, 'live').goal.status, 'cleared');
  assert.equal(projectSession(doc, 'live').goal.tokensUsed, undefined);
});

test('composer restores explicit MCP and Role choices without replaying a local frozen selection', () => {
  const doc = new LoroDoc();
  const history = doc.getList('history');
  history.push({
    id: 'off',
    role: 'user',
    inputConfig: {
      mcpServerIds: [],
      agentRoleId: null,
      frozenRole: { modelId: 'private-local-selection' },
    },
    items: [],
  });
  doc.commit();
  assert.deepEqual(projectSession(doc, 'live').composer, {
    mcpServerIds: [],
    agentRoleId: null,
  });
  history.push({
    id: 'on',
    role: 'user',
    inputConfig: {
      mcpServerIds: ['workspace-files'],
      agentRoleId: 'reviewer',
      agentRoleRevision: 3,
    },
    items: [],
  });
  doc.commit();
  assert.deepEqual(projectSession(doc, 'live').composer, {
    mcpServerIds: ['workspace-files'],
    agentRoleId: 'reviewer',
    agentRoleRevision: 3,
  });
  history.push({
    id: 'invalid',
    role: 'user',
    inputConfig: {
      mcpServerIds: ['bad id'],
      agentRoleId: 'bad\nrole',
      agentRoleRevision: -1,
    },
    items: [],
  });
  doc.commit();
  assert.deepEqual(projectSession(doc, 'live').composer, {});
});

test('session quota stays inside its agent config and selected model tier', () => {
  const snapshot = (id, usedPercent, limitName) => ({
    limitId: id,
    limitName,
    scope: { providerId: 'codex' },
    windows: [{ usedPercent, windowDurationSeconds: 18000 }],
  });
  const agent = (id, env = {}) => ({
    key: ['agentConfig', id],
    value: {
      id,
      machineId: 'm',
      name: id,
      agentType: 'codex',
      cliType: 'builtin',
      env,
    },
  });
  const usage = projectAgentUsage(
    [
      agent('a'),
      agent('b'),
      agent('custom', { OPENAI_API_KEY: 'private-key' }),
      {
        key: ['rateLimit', 'a', 'codex', 'codex'],
        value: snapshot('codex', 12),
      },
      {
        key: ['rateLimit', 'a', 'codex', 'codex_bengalfox'],
        value: snapshot('codex_bengalfox', 0, 'Codex Spark'),
      },
      {
        key: ['rateLimit', 'b', 'codex', 'codex'],
        value: snapshot('codex', 91),
      },
      { key: ['rateLimit', 'codex', 'codex'], value: snapshot('codex', 77) },
    ],
    'm',
  );
  const session = {
    agentConfigId: 'a',
    cliType: 'builtin',
    agentType: 'codex',
  };
  assert.equal(
    selectSessionQuotas(session, usage, 'gpt-6')[0].windows[0].usedPercent,
    12,
  );
  assert.equal(
    selectSessionQuotas(session, usage, 'codex-spark')[0].windows[0]
      .usedPercent,
    0,
  );
  assert.equal(
    selectSessionQuotas({ ...session, agentConfigId: 'b' }, usage, 'gpt-6')[0]
      .windows[0].usedPercent,
    91,
  );
  assert.deepEqual(
    selectSessionQuotas({ ...session, agentConfigId: 'missing' }, usage),
    [],
  );
  assert.deepEqual(
    selectSessionQuotas({ ...session, agentConfigId: 'custom' }, usage),
    [],
  );
  assert.equal(
    selectSessionQuotas(
      { cliType: 'builtin', agentType: 'codex' },
      usage,
      'gpt-6',
    )[0].windows[0].usedPercent,
    77,
    'Legacy provider quotas only apply to legacy sessions without config provenance',
  );
  const merged = mergeAgentQuotas(
    legacyAgentQuotas({ 'provider::b::codex::codex': snapshot('codex', 88) }),
    usage.quotas.filter((quota) => quota.agentConfigId === 'a'),
  );
  assert.ok(
    merged.some(
      (quota) =>
        quota.agentConfigId === 'b' && quota.windows[0].usedPercent === 88,
    ),
  );
  assert.ok(!JSON.stringify(usage).includes('private-key'));
});
