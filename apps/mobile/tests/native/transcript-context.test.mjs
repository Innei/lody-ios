import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { LoroDoc } from 'loro-crdt/base64';
import { projectRows } from '../../../../packages/cloud-runtime/src/protocol/catalog.ts';
import {
  projectAgentUsage,
  legacyAgentQuotas,
  mergeAgentQuotas,
  selectSessionQuotas,
} from '../../../../packages/cloud-runtime/src/protocol/agent-usage.ts';
import {
  collectPendingScheduledTasksFromHistory,
  resolveFireMs,
} from '../../../../packages/cloud-runtime/src/protocol/scheduled-tasks-from-history.ts';
import { nextCronFireMs } from '../../../../packages/cloud-runtime/src/protocol/cron-next-fire.ts';
import {
  readContextWindowUsage,
  readMessageAuthor,
} from '../../../../packages/cloud-runtime/src/protocol/transcript-context.ts';

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

test('warnings, proposals, file lifecycle and frozen authors survive projection without private fields', () => {
  const doc = new LoroDoc();
  const history = doc.getList('history');
  history.push({
    id: 'user',
    role: 'user',
    userId: 'human',
    author: {
      v: 1,
      kind: 'agent',
      sessionId: 'source',
      turnId: 'turn',
      name: 'Codex',
      role: { id: 'reviewer', revision: 3, name: 'Reviewer', emoji: '🔎' },
      env: { API_KEY: 'private-author' },
    },
    items: [{ type: 'text', text: 'Review this' }],
  });
  history.push({
    id: 'reply',
    role: 'assistant',
    finished: true,
    acpTurnId: 'native-turn',
    items: [
      {
        type: 'system_notice',
        name: 'agent_warning',
        meta: {
          message: 'The provider is retrying.',
          source: 'codex',
          token: 'private-notice',
        },
      },
      {
        type: 'system_notice',
        name: 'schedule_proposal',
        meta: {
          proposalId: 'proposal',
          title: 'Review weekly',
          prompt: 'Review the changelog',
          rule: { kind: 'weekly', weekdays: [1], hour: 9, minute: 0 },
          secret: 'private-proposal',
        },
      },
      {
        type: 'file',
        fileId: 'artifact',
        fileName: 'report.pdf',
        sizeBytes: 2048,
        transport: 'local',
        textPreview: false,
        uploadedAt: 1_900_000_000_000,
        sourcePath: 'reports/report.pdf',
        body: 'private-file-body',
      },
      {
        type: 'file',
        fileId: 'invalid-path',
        fileName: 'report.txt',
        sourcePath: '..\\secrets.txt',
      },
    ],
  });
  doc.commit();
  const projected = projectSession(doc, 'live');
  assert.equal(projected.entries[0].author.role.name, 'Reviewer');
  assert.equal(
    projected.entries[0].userId,
    undefined,
    'An agent author must never masquerade as its dispatching human',
  );
  const reply = projected.entries[1];
  assert.equal(reply.acpTurnId, 'native-turn');
  assert.equal(reply.items[0].meta.message, 'The provider is retrying.');
  assert.equal(reply.items[1].proposal.proposalId, 'proposal');
  assert.equal(reply.items[2].file.transport, 'local');
  assert.equal(reply.items[2].file.sourcePath, 'reports/report.pdf');
  assert.equal(reply.items[3].file.sourcePath, undefined);
  assert.ok(
    !/private-author|private-notice|private-proposal|private-file-body/.test(
      JSON.stringify(projected),
    ),
  );
  assert.equal(
    readMessageAuthor({ v: 2, kind: 'agent', name: 'future' }),
    undefined,
  );
});

test('catalog restores reported context and provenance, while malformed or missing telemetry stays absent', () => {
  const metadata = {
    id: 's',
    machineId: 'm',
    contextWindowUsage: { size: 200000, used: 0, secret: 'private-context' },
    agentConfigId: 'provider-a',
    scheduleId: 'schedule',
    userId: 'owner',
    pinnedHistoryId: 'input',
  };
  const rows = [
    { key: ['e', 'session-s'], value: true },
    { key: ['m', 'session-s'], value: metadata },
  ];
  const session = projectRows(rows, 'meta').sessions[0];
  assert.deepEqual(session.contextWindowUsage, { size: 200000, used: 0 });
  assert.equal(session.agentConfigId, 'provider-a');
  assert.equal(session.scheduleId, 'schedule');
  assert.ok(!JSON.stringify(session).includes('private-context'));
  for (const invalid of [
    undefined,
    {},
    { size: 0, used: 0 },
    { size: 200000 },
    { size: 200000, used: -1 },
    { size: 200000, used: '4' },
  ])
    assert.equal(readContextWindowUsage(invalid), undefined);
  assert.equal(
    readContextWindowUsage({ size: 100, used: 110 }).used,
    110,
    'Reported tokens remain exact even when the visual percentage is clamped',
  );
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

test('scheduled summaries retain the machine clock, committed one-shot fire, latest wakeup and deletes', () => {
  const created = Date.parse('2026-10-12T08:15:00+08:00');
  const call = (name, id, rawInput, extra = {}) => ({
    type: 'tool_call',
    toolName: name,
    title: 'A human-readable action',
    toolCallId: id,
    status: 'completed',
    recordedAtMs: created,
    rawInput,
    ...extra,
  });
  const items = [
    call(
      'CronCreate',
      'cron-delete',
      { cron: '0 9 * * 1-5', recurring: true, prompt: 'Review daily' },
      { rawOutput: 'id: old-job', schedulingTimeZone: 'Asia/Tokyo' },
    ),
    call(
      'CronCreate',
      'cron-once',
      { cron: '30 8 12 10 *', recurring: false, prompt: 'Review once' },
      {
        rawOutput: 'nextFireAt: 2026-10-12T08:30:00+08:00',
        schedulingTimeZone: 'Asia/Singapore',
      },
    ),
    call('ScheduleWakeup', 'wake-old', {
      delaySeconds: 10,
      reason: 'Old wakeup',
    }),
    call('ScheduleWakeup', 'wake-new', {
      delaySeconds: 120,
      reason: 'Newest wakeup',
    }),
    call('CronDelete', 'delete', { id: 'old-job' }),
    call('CronCreate', 'failed', { cron: '* * * * *' }, { status: 'failed' }),
  ];
  const tasks = collectPendingScheduledTasksFromHistory([
    { startedAt: created - 60000, endedAt: created + 86400000, items },
  ]);
  assert.equal(tasks.length, 2);
  const wakeup = tasks.find((task) => task.kind === 'wakeup');
  assert.equal(wakeup.summary, 'Newest wakeup');
  assert.equal(wakeup.scheduledForMs, created + 120000);
  const once = tasks.find((task) => task.kind === 'cron');
  assert.equal(once.timeZone, 'Asia/Singapore');
  assert.equal(
    resolveFireMs(once, created + 86400000),
    Date.parse('2026-10-12T08:30:00+08:00'),
    'A fired one-shot must not jump to next year after merged turn timestamps advance',
  );
  assert.equal(
    nextCronFireMs(
      '0 9 * * 1-5',
      Date.parse('2026-10-12T00:00:00Z'),
      'Asia/Tokyo',
    ),
    Date.parse('2026-10-13T00:00:00Z'),
  );
  assert.equal(
    nextCronFireMs('bad-expression', created, 'Asia/Tokyo'),
    undefined,
  );
});

test('legacy one-shot cron exposes its anchored fire time across history updates', () => {
  const created = Date.parse('2026-09-07T08:15:00Z');
  const fire = Date.parse('2026-09-07T09:00:00Z');
  const doc = new LoroDoc();
  const history = doc.getList('history');
  history.push({
    id: 'legacy-cron',
    role: 'assistant',
    startedAt: created,
    finished: true,
    items: [
      {
        type: 'tool_call',
        toolName: 'CronCreate',
        toolCallId: 'legacy-job',
        status: 'completed',
        recordedAtMs: created,
        schedulingTimeZone: 'UTC',
        rawInput: { cron: '0 9 * * *', recurring: false },
      },
    ],
  });
  doc.commit();
  const legacy = projectSession(doc, 'live').scheduledTasks[0];
  assert.equal(legacy.scheduledForMs, undefined);
  assert.equal(legacy.nextFireMs, fire);
  assert.equal(resolveFireMs(legacy, fire + 60000), fire);
  history.push({
    id: 'unrelated',
    role: 'assistant',
    endedAt: fire + 86400000,
    finished: true,
    items: [{ type: 'text', text: 'Another reply' }],
  });
  doc.commit();
  assert.equal(
    projectSession(doc, 'live').scheduledTasks[0].nextFireMs,
    fire,
    'Reprojection must preserve the past one-shot time so the native summary can clear',
  );
});
