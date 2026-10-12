import assert from 'node:assert/strict';
import { test } from 'node:test';
import { build } from 'esbuild';
import {
  buildScheduleRow,
  canonicalScheduleJson,
  matchingScheduleRuntime,
  parseScheduleDocument,
  parseScheduleProposal,
  readScheduleRegistry,
  scheduleFingerprint,
  scheduleOwnSessionId,
  validateScheduleDraft,
  validateScheduleRequest,
} from '@lody/cloud-runtime/protocol/schedules';
import {
  nextScheduleSlot,
  previewSchedule,
  ruleToTrigger,
  triggerToRule,
  validateScheduleTrigger,
  zonedLocalInputToInstant,
} from '@lody/cloud-runtime/protocol/schedule-time';

const bundle = await build({
  stdin: {
    contents: `export { planScheduleMutation, writeScheduleDocument, scheduleContext } from './packages/cloud-runtime/src/runtime/schedules.ts'; export { Flock } from '@loro-dev/flock-wasm/base64'; export { LoroDoc } from 'loro-crdt/base64'; export {pendingScheduleStore,performScheduleWrite} from './apps/mobile/src/features/schedules/pending.ts';export {scheduleForDestinationSession,scheduleRuleCandidate,scheduleDisplayTimeZone,dateLabel,frequencyLabel} from './apps/mobile/src/features/schedules/model.ts'; export {requestSchedules} from './apps/mobile/src/cloud/schedules.ts';`,
    resolveDir: process.cwd(),
  },
  bundle: true,
  format: 'esm',
  platform: 'browser',
  write: false,
  plugins: [
    {
      name: 'offline-storage',
      setup(build) {
        build.onResolve({ filter: /^@lody-ios\/kit$/ }, () => ({
          path: 'kit',
          namespace: 'offline-storage',
        }));
        build.onLoad({ filter: /.*/, namespace: 'offline-storage' }, () => ({
          contents: `export const readLocalValue=async key => globalThis.__scheduleLocal.get(key); export const writeLocalValue=async(key,value) => globalThis.__scheduleLocal.set(key,value); export const clearLocalValues=async() => globalThis.__scheduleLocal.clear(); export const scheduleCommand=payload=>globalThis.__scheduleNative(payload);`,
        }));
      },
    },
  ],
});
globalThis.__scheduleLocal = new Map();
const {
  planScheduleMutation,
  writeScheduleDocument,
  scheduleContext,
  Flock,
  LoroDoc,
  pendingScheduleStore,
  performScheduleWrite,
  scheduleForDestinationSession,
  scheduleRuleCandidate,
  scheduleDisplayTimeZone,
  dateLabel,
  frequencyLabel,
  requestSchedules,
} = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);
const now = Date.parse('2026-09-06T12:00:00Z');
const draft = {
  title: 'Daily review',
  prompt: 'Review today’s work.',
  machineId: 'studio',
  trigger: { kind: 'manual' },
  agent: {
    agentConfigId: 'codex',
    modeId: 'agent',
    configOptionValues: { fast: false },
  },
  destination: { kind: 'new_session' },
  misfirePolicy: { kind: 'run_once' },
  overlapPolicy: 'queue_one',
  retryPolicy: { dispatchMaxAttempts: 5, dispatchMaxAgeMs: 86_400_000 },
};
const create = {
  workspaceId: 'workspace',
  action: 'create',
  scheduleId: 'task',
  requestId: 'create-1',
  draft,
};
function registry() {
  return new Flock(`schedules-test-${crypto.randomUUID()}`);
}
async function committed(flock) {
  const document = planScheduleMutation(
    create,
    undefined,
    flock,
    'owner',
    now,
  ).document;
  flock.set(['schedule', 'task'], await buildScheduleRow(document));
  return document;
}

test('named rules use the machine clock, aligned steps and stable interval anchors', () => {
  assert.equal(
    previewSchedule(
      ruleToTrigger(
        { kind: 'daily', hour: 9, minute: 0 },
        now,
        'Asia/Shanghai',
      ),
      0,
      now,
      1,
    )[0],
    Date.parse('2026-09-07T01:00:00Z'),
  );
  assert.equal(
    previewSchedule(
      ruleToTrigger(
        { kind: 'daily', hour: 9, minute: 0, timeZone: 'UTC' },
        now,
        'Asia/Shanghai',
      ),
      0,
      now,
      1,
    )[0],
    Date.parse('2026-09-07T09:00:00Z'),
  );
  assert.equal(
    previewSchedule(
      ruleToTrigger({ kind: 'hours', every: 6 }, now, 'Asia/Shanghai'),
      0,
      now,
      1,
    )[0],
    Date.parse('2026-09-06T16:00:00Z'),
  );
  const interval = ruleToTrigger(
    { kind: 'minutes', every: 7 },
    now,
    'Asia/Shanghai',
  );
  assert.equal(interval.kind, 'interval');
  assert.equal(nextScheduleSlot(interval, now, now + 60_000), now + 7 * 60_000);
  assert.deepEqual(
    triggerToRule(
      { kind: 'cron', expression: '30 7 * * MON-FRI', timeZone: 'UTC' },
      'Asia/Shanghai',
    ),
    { kind: 'weekdays', hour: 7, minute: 30, timeZone: 'UTC' },
  );
  assert.equal(
    triggerToRule(
      { kind: 'cron', expression: '0 9 * * 0-7', timeZone: 'UTC' },
      'UTC',
    ).kind,
    'daily',
  );
  assert.equal(
    triggerToRule(
      { kind: 'cron', expression: '0 9,17 * * *', timeZone: 'UTC' },
      'UTC',
    ),
    null,
  );
  assert.throws(() =>
    ruleToTrigger(
      { kind: 'weekly', hour: 9, minute: 0, weekdays: [] },
      now,
      'UTC',
    ),
  );
  assert.throws(() =>
    ruleToTrigger(
      { kind: 'monthly', hour: 9, minute: 0, days: [] },
      now,
      'UTC',
    ),
  );
  assert.deepEqual(previewSchedule({ kind: 'manual' }, 0, now), []);
  assert.deepEqual(
    previewSchedule(
      { kind: 'once', at: new Date(now - 1).toISOString() },
      0,
      now,
    ),
    [],
  );
});
test('calendar preview skips DST gaps, uses the first fold and skips nonexistent month dates', () => {
  const spring = {
    kind: 'cron',
    expression: '30 2 * * *',
    timeZone: 'America/New_York',
  };
  assert.deepEqual(
    previewSchedule(spring, 0, Date.parse('2026-03-07T08:00:00Z'), 1),
    [Date.parse('2026-03-09T06:30:00Z')],
  );
  const fall = {
    kind: 'cron',
    expression: '30 1 * * *',
    timeZone: 'America/New_York',
  };
  assert.deepEqual(
    previewSchedule(fall, 0, Date.parse('2026-11-01T04:00:00Z'), 2),
    [Date.parse('2026-11-01T05:30:00Z'), Date.parse('2026-11-02T06:30:00Z')],
  );
  assert.equal(
    zonedLocalInputToInstant('2026-03-08T02:30', 'America/Los_Angeles'),
    Date.parse('2026-03-08T10:30:00Z'),
  );
  assert.equal(
    zonedLocalInputToInstant('2026-11-01T01:30', 'America/Los_Angeles'),
    Date.parse('2026-11-01T08:30:00Z'),
  );
  assert.equal(
    previewSchedule(
      { kind: 'cron', expression: '0 9 31 * *', timeZone: 'UTC' },
      0,
      Date.parse('2026-04-01T00:00:00Z'),
      1,
    )[0],
    Date.parse('2026-05-31T09:00:00Z'),
  );
  assert.equal(
    nextScheduleSlot(
      { kind: 'cron', expression: '0 9 31 2 *', timeZone: 'UTC' },
      0,
      now,
    ),
    undefined,
  );
  assert.equal(
    previewSchedule(
      { kind: 'cron', expression: '0 9 29 2 *', timeZone: 'UTC' },
      0,
      now,
      1,
    )[0],
    Date.parse('2028-02-29T09:00:00Z'),
  );
});
test('calendar schedule dates use their rule zone even when the machine is elsewhere', () => {
  const trigger = ruleToTrigger(
    { kind: 'weekdays', hour: 9, minute: 0, timeZone: 'Asia/Shanghai' },
    now,
    'America/New_York',
  );
  const next = previewSchedule(
    trigger,
    0,
    Date.parse('2026-10-11T12:00:00Z'),
    1,
  )[0];
  assert.equal(next, Date.parse('2026-10-12T01:00:00Z'));
  const zone = scheduleDisplayTimeZone(trigger, 'America/New_York');
  assert.equal(zone, 'Asia/Shanghai');
  assert.match(frequencyLabel({ trigger }, zone), /09:00/);
  assert.match(dateLabel(next, zone), /Oct 12, 2026.*9:00.*AM/);
  assert.match(dateLabel(next, 'America/New_York'), /Oct 11, 2026.*9:00.*PM/);
  assert.equal(
    scheduleDisplayTimeZone(
      { kind: 'once', at: new Date(next).toISOString() },
      'America/New_York',
    ),
    'America/New_York',
  );
  assert.equal(
    scheduleDisplayTimeZone(
      {
        kind: 'interval',
        everyMs: 60000,
        anchorAt: new Date(next).toISOString(),
      },
      'America/New_York',
    ),
    'America/New_York',
  );
  assert.equal(scheduleDisplayTimeZone({ kind: 'manual' }), 'UTC');
});
test('an invalid edited rule cannot fall back to the previous valid task rule', () => {
  const zone = 'Asia/Shanghai';
  const original = ruleToTrigger(
    { kind: 'weekdays', hour: 9, minute: 0 },
    now,
    zone,
  );
  assert.equal(
    scheduleRuleCandidate(
      original,
      { kind: 'weekly', weekdays: [], hour: 9, minute: 0 },
      zone,
      now,
    ),
    undefined,
  );
  assert.equal(
    scheduleRuleCandidate(
      original,
      { kind: 'monthly', days: [], hour: 9, minute: 0 },
      zone,
      now,
    ),
    undefined,
  );
  const repaired = scheduleRuleCandidate(
    original,
    { kind: 'weekly', weekdays: [3], hour: 9, minute: 0 },
    zone,
    now,
  );
  assert.equal(repaired.expression, '0 9 * * 3');
  assert.equal(repaired.timeZone, zone);
  const interval = ruleToTrigger({ kind: 'minutes', every: 7 }, now, zone);
  assert.strictEqual(
    scheduleRuleCandidate(
      interval,
      triggerToRule(interval, zone),
      zone,
      now + 3_600_000,
    ),
    interval,
    'Opening an unchanged interval must preserve its anchor',
  );
});
test('trust boundary rejects credentials, invalid commands, excess UTF-8 bytes and nonportable cron', () => {
  assert.throws(() =>
    validateScheduleDraft({
      ...draft,
      agent: {
        agentConfigId: 'codex',
        configOptionValues: { api_key: 'secret' },
      },
    }),
  );
  assert.throws(() =>
    validateScheduleDraft({ ...draft, prompt: '🙂'.repeat(9000) }),
  );
  assert.throws(() =>
    validateScheduleRequest({ ...create, action: 'not-a-command' }),
  );
  assert.throws(() =>
    validateScheduleRequest({ ...create, userId: 'other-user' }),
  );
  assert.throws(() =>
    validateScheduleTrigger({ kind: 'once', at: '2026-09-07T09:00:00' }),
  );
  assert.throws(() =>
    validateScheduleTrigger({
      kind: 'cron',
      expression: '0 0 9 * * *',
      timeZone: 'UTC',
    }),
  );
  assert.throws(() =>
    validateScheduleTrigger({
      kind: 'cron',
      expression: '0 9 * * MON#2',
      timeZone: 'UTC',
    }),
  );
  assert.throws(() =>
    validateScheduleTrigger({
      kind: 'cron',
      expression: '0 9 * * *',
      timeZone: 'made-up-zone',
    }),
  );
  assert.throws(() =>
    validateScheduleRequest({
      ...create,
      draft: {
        ...draft,
        trigger: {
          kind: 'cron',
          expression: ' '.repeat(256) + '0 9 * * *',
          timeZone: 'UTC',
        },
      },
    }),
  );
  assert.throws(() =>
    validateScheduleRequest({
      ...create,
      draft: {
        ...draft,
        trigger: {
          kind: 'once',
          at: '2026-09-07T09:00:00.' + '0'.repeat(100) + 'Z',
        },
      },
    }),
  );
});
test('the mobile transport carries full legal Unicode and escaped task configurations', async () => {
  const controls = (size) => '\u0000'.repeat(size);
  const large = {
    ...create,
    workspaceId: controls(4096),
    scheduleId: 's'.repeat(50),
    requestId: 'r'.repeat(50),
    draft: {
      ...draft,
      title: controls(200),
      machineId: controls(4096),
      prompt: controls(32768),
      trigger: {
        kind: 'cron',
        expression: ' '.repeat(247) + '0 9 * * *',
        timeZone: 'UTC',
      },
      agent: {
        agentConfigId: controls(4096),
        modeId: controls(4096),
        modelId: controls(4096),
        memory: { providerId: controls(100), memoryId: controls(200) },
        configOptionValues: Object.fromEntries(
          Array.from({ length: 50 }, (_, i) => [
            controls(98) + String(i).padStart(2, '0'),
            controls(1024),
          ]),
        ),
      },
      project: {
        kind: 'local',
        localProjectId: controls(4096),
        branch: controls(4096),
        githubRepoFullName: controls(4096),
        useWorktree: false,
      },
      destination: { kind: 'existing_session', sessionId: controls(4096) },
    },
    proposal: {
      sessionId: controls(4096),
      entryId: controls(4096),
      itemIndex: 100000,
      proposalId: 'p'.repeat(50),
    },
  };
  const chinese = {
    ...create,
    draft: {
      ...draft,
      prompt: 'p'.repeat(32768),
      agent: {
        agentConfigId: 'codex',
        configOptionValues: Object.fromEntries(
          Array.from({ length: 50 }, (_, i) => [
            'choice' + i,
            '中'.repeat(1024),
          ]),
        ),
      },
    },
  };
  const received = [];
  globalThis.__scheduleNative = async (payload) => {
    const input = validateScheduleRequest(JSON.parse(payload));
    assert.ok(Buffer.byteLength(payload) <= 832 * 1024);
    received.push(input);
    return JSON.stringify({ ok: true, scheduleId: input.scheduleId });
  };
  try {
    for (const request of [large, chinese]) {
      validateScheduleRequest(request);
      assert.ok(Buffer.byteLength(JSON.stringify(request)) > 128 * 1024);
      assert.deepEqual(await requestSchedules(request), {
        ok: true,
        scheduleId: request.scheduleId,
      });
    }
    assert.deepEqual(received, [large, chinese]);
  } finally {
    delete globalThis.__scheduleNative;
  }
});
test('an interrupted doc-first create replays once and preserves native Loro containers', async () => {
  const flock = registry(),
    first = planScheduleMutation(
      create,
      undefined,
      flock,
      'owner',
      now,
    ).document;
  assert.equal(
    readScheduleRegistry(flock.scan()).rows.length,
    0,
    'An orphan definition must never grant execution',
  );
  const doc = new LoroDoc();
  try {
    writeScheduleDocument(doc, first);
    assert.deepEqual(parseScheduleDocument(doc.toJSON(), 'task'), first);
    const replay = planScheduleMutation(
      create,
      first,
      flock,
      'owner',
      now + 1000,
    ).document;
    assert.equal(replay.timeline.length, 1);
    writeScheduleDocument(doc, replay);
    assert.equal(doc.getList('timeline').length, 1);
    flock.set(['schedule', 'task'], await buildScheduleRow(replay));
    assert.equal(readScheduleRegistry(flock.scan()).rows.length, 1);
    assert.throws(
      () =>
        planScheduleMutation(
          { ...create, draft: { ...draft, prompt: 'Different' } },
          replay,
          flock,
          'owner',
          now,
        ),
      /idempotency/,
    );
    assert.throws(
      () => planScheduleMutation(create, replay, flock, 'stranger', now),
      /idempotency/,
    );
  } finally {
    doc.free();
  }
});
test('run retries do not duplicate dispatch and pause/resume use the exact activation gate', async () => {
  const flock = registry(),
    document = await committed(flock);
  const run = {
    workspaceId: 'workspace',
    action: 'run',
    scheduleId: 'task',
    requestId: 'run-1',
  };
  const first = planScheduleMutation(run, document, flock, 'owner', now);
  flock.set(first.key, first.value);
  assert.deepEqual(
    planScheduleMutation(run, document, flock, 'owner', now + 1000),
    {},
  );
  assert.equal([...flock.scan({ prefix: ['manual', 'task'] })].length, 1);
  assert.throws(
    () => planScheduleMutation(run, document, flock, 'stranger', now),
    /owner/,
  );
  const pause = {
    workspaceId: 'workspace',
    action: 'pause',
    scheduleId: 'task',
    requestId: 'pause-1',
  };
  const paused = planScheduleMutation(
    pause,
    document,
    flock,
    'owner',
    now + 1000,
  ).document;
  assert.equal(paused.definition.enabled, false);
  assert.equal(
    paused.definition.activationId,
    document.definition.activationId,
  );
  assert.equal(
    planScheduleMutation(pause, paused, flock, 'owner', now + 2000).document
      .timeline.length,
    2,
  );
  flock.set(['schedule', 'task'], await buildScheduleRow(paused));
  const resume = { ...pause, action: 'resume', requestId: 'resume-1' };
  const resumed = planScheduleMutation(
    resume,
    paused,
    flock,
    'owner',
    now + 3000,
  ).document;
  assert.equal(resumed.definition.activationId, 'resume-1');
  assert.equal(resumed.definition.activeFrom, now + 3000);
  assert.throws(
    () => planScheduleMutation(run, resumed, flock, 'owner', now + 5000),
    /idempotency/,
  );
});
test('tombstones win over stale saves while preserving results and definitions', async () => {
  const flock = registry(),
    document = await committed(flock),
    remove = { workspaceId: 'workspace', action: 'delete', scheduleId: 'task' };
  const mutation = planScheduleMutation(remove, document, flock, 'owner', now);
  flock.set(mutation.key, mutation.value);
  flock.set(['schedule', 'task'], await buildScheduleRow(document));
  assert.deepEqual(readScheduleRegistry(flock.scan()).rows, []);
  assert.deepEqual(
    planScheduleMutation(remove, undefined, flock, 'owner', now),
    {},
  );
  assert.throws(
    () =>
      planScheduleMutation(
        { ...create, action: 'edit' },
        document,
        flock,
        'owner',
        now,
      ),
    /deleted/,
  );
  assert.equal(document.prompt, draft.prompt);
});
test('execution fingerprints ignore cosmetics but reject stale runtime projections', async () => {
  const flock = registry(),
    document = await committed(flock),
    fingerprint = await scheduleFingerprint(document);
  assert.equal(
    await scheduleFingerprint({
      ...document,
      definition: {
        ...document.definition,
        title: 'Renamed',
        updatedAt: now + 1000,
      },
    }),
    fingerprint,
  );
  assert.notEqual(
    await scheduleFingerprint({ ...document, prompt: 'Changed instructions' }),
    fingerprint,
  );
  const row = await buildScheduleRow(document),
    runtime = {
      scheduleId: 'task',
      machineId: 'studio',
      activationId: row.activationId,
      observedDefinitionFingerprint: row.definitionFingerprint,
      updatedAt: now,
      nextScheduledAt: now + 1000,
    };
  assert.equal(matchingScheduleRuntime(row, [runtime]), runtime);
  assert.equal(
    matchingScheduleRuntime(row, [{ ...runtime, activationId: 'stale' }]),
    undefined,
  );
  assert.equal(
    matchingScheduleRuntime(row, [
      { ...runtime, observedDefinitionFingerprint: 'stale' },
    ]),
    undefined,
  );
  assert.equal(
    await scheduleOwnSessionId('task', 0),
    await scheduleOwnSessionId('task', 0),
  );
  assert.notEqual(
    await scheduleOwnSessionId('task', 0),
    await scheduleOwnSessionId('task', 1),
  );
});
test('catalog projection fences machine ownership/support and does not invent connectivity', () => {
  const meta = registry(),
    machine = registry();
  meta.set(['e', 'machine-studio'], true);
  meta.set(['m', 'machine-studio'], {
    name: 'Studio Mac',
    ownerUserId: 'owner',
    protocolCapabilities: { schedules: 2 },
    timeZone: 'Asia/Shanghai',
  });
  machine.set(['agentConfig', 'codex'], {
    id: 'codex',
    machineId: 'studio',
    name: 'Codex',
    cliType: 'builtin',
    agentType: 'codex',
  });
  const context = scheduleContext({
    meta,
    machines: new Map([['studio', machine]]),
    presence: { state: 'unknown', onlineMachineIds: [] },
  });
  assert.equal(context.machines[0].state, 'unknown');
  assert.equal(context.machines[0].timeZone, 'Asia/Shanghai');
  assert.equal(context.machines[0].supported, true);
  meta.set(['m', 'machine-studio', 'protocolCapabilities'], { schedules: 1 });
  assert.equal(
    scheduleContext({
      meta,
      machines: new Map([['studio', machine]]),
      presence: { state: 'live', onlineMachineIds: [] },
    }).machines[0].supported,
    false,
  );
});
test('proposals remain inert metadata and reject malformed or credential-bearing targets', () => {
  const proposal = {
    proposalId: 'proposal',
    title: 'Review',
    prompt: 'Review changes.',
    rule: { kind: 'weekly', weekdays: [1, 3], hour: 9, minute: 30 },
    destination: { kind: 'own_session' },
    target: { agentRoleId: 'reviewer', machineId: 'studio' },
  };
  assert.equal(parseScheduleProposal(proposal).outcome, undefined);
  assert.equal(
    parseScheduleProposal({
      ...proposal,
      rule: { kind: 'weekly', weekdays: [], hour: 9, minute: 0 },
    }),
    undefined,
  );
  assert.equal(
    parseScheduleProposal({ ...proposal, target: { token: 'secret' } }),
    undefined,
  );
  assert.equal(
    parseScheduleProposal({ ...proposal, prompt: '🙂'.repeat(9000) }),
    undefined,
  );
});

test('uncertain writes survive reopening and explicit retry keeps the same identity', async () => {
  const store = pendingScheduleStore('owner', 'workspace'),
    seen = [];
  let created = false;
  const service = async (request) => {
    seen.push(canonicalScheduleJson(request));
    if (!created) {
      created = true;
      throw Object.assign(new Error('Lost acknowledgement'), {
        code: 'schedule_write_unknown',
      });
    }
    return { ok: true, scheduleId: request.scheduleId };
  };
  await assert.rejects(performScheduleWrite(create, service, store), /Lost/);
  const restored = (await pendingScheduleStore('owner', 'workspace').read())[0];
  assert.deepEqual(restored, create);
  await performScheduleWrite(restored, service, store);
  assert.equal(seen.length, 2);
  assert.equal(seen[0], seen[1]);
  assert.deepEqual(await store.read(), []);
  assert.deepEqual(
    await pendingScheduleStore('other-account', 'workspace').read(),
    [],
  );
});
test('an existing conversation moves calendar rules to its machine while preserving instants and interval anchors', () => {
  const session = {
    id: 'chat',
    title: 'Chat',
    machineId: 'singapore',
    agentConfigId: 'codex-sg',
    ownerId: 'owner',
  };
  const context = {
    machines: [{ id: 'singapore', timeZone: 'Asia/Singapore' }],
    agents: [
      {
        id: 'codex-sg',
        machineId: 'singapore',
        name: 'Codex',
        cliType: 'builtin',
        agentType: 'codex',
      },
    ],
    capabilities: [],
    sessions: [session],
  };
  const calendar = {
    ...draft,
    trigger: {
      kind: 'cron',
      expression: '0 9 * * *',
      timeZone: 'America/New_York',
    },
  };
  const moved = scheduleForDestinationSession(calendar, session, context);
  assert.equal(moved.machineId, 'singapore');
  assert.equal(moved.trigger.timeZone, 'Asia/Singapore');
  assert.equal(
    previewSchedule(moved.trigger, 0, now, 1)[0],
    Date.parse('2026-09-07T01:00:00Z'),
  );
  for (const trigger of [
    { kind: 'once', at: '2026-09-07T09:00:00.000Z' },
    {
      kind: 'interval',
      everyMs: 420_000,
      anchorAt: '2026-09-01T00:00:00.000Z',
    },
  ])
    assert.equal(
      scheduleForDestinationSession({ ...draft, trigger }, session, context)
        .trigger,
      trigger,
    );
});
