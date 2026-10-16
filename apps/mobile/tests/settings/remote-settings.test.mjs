import assert from 'node:assert/strict';
import test from 'node:test';
import { setLocale, t } from '../../src/lib/i18n/index.ts';
import {
  loadRemoteSettings,
  memoryRemoteSettingsCache,
  parseSavedRemoteSettings,
  remoteSettingsKey,
  remoteSettingsPlaceholder,
  remoteSettingsSections,
} from '../../src/features/settings/remote-settings.ts';

setLocale('zh-Hans');

const grok = {
  kind: 'agent',
  id: 'grok',
  name: 'Grok',
  machineId: 'm1',
  machineName: 'Studio',
  detail: 'grok',
};
const claude = {
  kind: 'agent',
  id: 'claude',
  name: 'Claude Code',
  machineId: 'm1',
  machineName: 'Studio',
  detail: 'claude',
};
const usage = {
  m1: {
    configs: [
      { id: 'grok', name: 'Grok', provider: 'grok', eligible: true },
      { id: 'claude', name: 'Claude Code', provider: 'claude', eligible: true },
    ],
    quotas: [],
  },
};

test('catalog agent configs never become the list when nothing is confirmed', () => {
  const sections = remoteSettingsSections({
    kind: 'agent',
    items: [],
    loading: true,
    error: '',
    connected: true,
    agentUsage: usage,
  });
  assert.deepEqual(
    sections.flatMap((section) => section.rows.map((row) => row.id)),
    [],
  );
  assert.equal(
    remoteSettingsPlaceholder({ items: [], loading: true, error: '' }),
    '正在读取远程设置…',
  );
});

test('confirmed cache keeps its order and shows the refresh time', () => {
  const sections = remoteSettingsSections({
    kind: 'agent',
    items: [grok, claude],
    loading: true,
    error: '',
    connected: true,
    agentUsage: usage,
    syncedAt: Date.parse('2026-09-12T12:00:00+08:00'),
    now: Date.parse('2026-09-12T12:03:00+08:00'),
  });
  assert.deepEqual(
    sections.flatMap((section) =>
      section.rows
        .filter((row) => row.id.startsWith('setting:'))
        .map((row) => row.id),
    ),
    ['setting:agent:m1:grok', 'setting:agent:m1:claude'],
  );
  assert.match(
    sections.find((section) => section.id === 'machine:m1').footer,
    /更新于/,
  );
  assert.equal(
    remoteSettingsPlaceholder({
      items: [grok],
      loading: true,
      error: '',
    }),
    '',
  );
});

test('agents on interleaved machines group together without merging identical names or ids', () => {
  const sections = remoteSettingsSections({
    kind: 'agent',
    items: [
      grok,
      { ...grok, machineId: 'm2', readOnly: true },
      claude,
      { ...grok, machineId: undefined, machineName: undefined },
    ],
    error: '',
    connected: true,
    agentUsage: usage,
    syncedAt: 1,
    now: 1000,
  });
  assert.deepEqual(
    sections
      .filter((group) => !group.id.endsWith(':usage'))
      .map((group) =>
        group.rows
          .filter((row) => row.id.startsWith('setting:'))
          .map((row) => row.id),
      ),
    [
      ['setting:agent:m1:grok', 'setting:agent:m1:claude'],
      ['setting:agent:m2:grok'],
      ['setting:agent::grok'],
    ],
  );
  assert.equal(sections[0].header, 'Studio');
  const second = sections.find((section) => section.id === 'machine:m2');
  assert.equal(second.header, 'Studio');
  assert.notEqual(sections[0].id, second.id);
  assert.equal(second.rows[0].action, false);
  assert.ok(sections.find((section) => section.id === 'machine:').header);
  assert.match(second.footer, /m2/);
  assert.match(second.footer, /更新于/);
});

test('live fetch replaces cache and writes the confirmed snapshot', async () => {
  const cache = memoryRemoteSettingsCache();
  cache.write('w1', 'agent', { items: [grok], syncedAt: 1 });
  let cached;
  let release;
  const pending = new Promise((resolve) => {
    release = resolve;
  });
  const loading = loadRemoteSettings({
    workspaceId: 'w1',
    kind: 'agent',
    cache,
    service: async () => pending,
    onCached: (saved) => {
      cached = saved;
    },
    now: 50,
  });
  await Promise.resolve();
  assert.deepEqual(
    cached.items.map((item) => item.id),
    ['grok'],
  );
  release([claude, grok]);
  const result = await loading;
  assert.deepEqual(
    result.live.items.map((item) => item.id),
    ['claude', 'grok'],
  );
  assert.equal(result.live.syncedAt, 50);
  assert.deepEqual(await cache.read('w1', 'agent'), result.live);
});

test('a failed refresh keeps the cached snapshot', async () => {
  const cache = memoryRemoteSettingsCache();
  cache.write('w1', 'agent', { items: [grok], syncedAt: 9 });
  const result = await loadRemoteSettings({
    workspaceId: 'w1',
    kind: 'agent',
    cache,
    service: async () => {
      throw new Error('offline');
    },
  });
  assert.equal(result.error, 'offline');
  assert.equal(result.live, undefined);
  assert.deepEqual((await cache.read('w1', 'agent')).items, [grok]);
});

test('saved snapshots reject catalog-shaped or cross-kind payloads', () => {
  assert.equal(
    remoteSettingsKey('u1', 'w1', 'agent'),
    'remote-settings:u1:w1:agent',
  );
  assert.equal(
    parseSavedRemoteSettings({ items: [grok], syncedAt: 1 }, 'agent')?.items[0]
      .id,
    'grok',
  );
  assert.equal(
    parseSavedRemoteSettings({ items: [grok], syncedAt: 1 }, 'machine'),
    null,
  );
  assert.equal(
    parseSavedRemoteSettings({ configs: usage.m1.configs }, 'agent'),
    null,
  );
});

const machines = [
  { kind: 'machine', id: 'owner-mac', name: 'Studio Mac', detail: 'macOS' },
  { kind: 'machine', id: 'team-mac', name: 'Studio Mac', readOnly: true },
];
const machineList = {
  kind: 'machine',
  items: machines,
  error: '',
  connected: true,
  syncedAt: 1,
  now: 1000,
  machinePresence: { state: 'live', onlineMachineIds: ['owner-mac'] },
};

test('same-name machines expose distinct identities, presence and edit permissions', () => {
  const [section] = remoteSettingsSections(machineList);
  const [owner, teammate] = section.rows;
  assert.equal(owner.title, teammate.title);
  assert.notEqual(owner.id, teammate.id);
  assert.match(owner.subtitle, /owner-mac/);
  assert.match(teammate.subtitle, /team-mac/);
  assert.ok(owner.subtitle.includes(t('devices.online')));
  assert.ok(teammate.subtitle.includes(t('devices.offline')));
  assert.equal(owner.action, true);
  assert.equal(teammate.action, false);
  assert.equal(teammate.disclosure, false);
  assert.ok(teammate.subtitle.includes(t('settings.remote.readOnly')));
});

test('disconnected or failed machine refresh never presents stale presence as online', () => {
  for (const state of [{ connected: false }, { error: 'refresh failed' }]) {
    const [section] = remoteSettingsSections({ ...machineList, ...state });
    assert.ok(
      section.rows.every((row) => row.subtitle.includes(t('devices.unknown'))),
    );
    assert.ok(
      section.rows.every((row) => !row.subtitle.includes(t('devices.online'))),
    );
    assert.deepEqual(
      section.rows.map((row) => row.title),
      ['Studio Mac', 'Studio Mac'],
    );
    assert.ok(section.footer.includes(t('settings.remote.machineCached')));
    assert.ok(
      section.footer.includes(
        t('settings.remote.syncedAt', { time: t('time.justNow') }),
      ),
    );
  }
  const [section] = remoteSettingsSections({
    ...machineList,
    machinePresence: { state: 'unknown', onlineMachineIds: [] },
  });
  assert.ok(
    section.rows.every((row) => row.subtitle.includes(t('devices.unknown'))),
  );
});

const codexAgent = {
  kind: 'agent',
  id: 'codex-one',
  name: 'Codex',
  detail: 'codex',
  machineId: 'm1',
  machineName: 'Studio',
};
const subscription = {
  configs: [
    { id: 'codex-one', provider: 'codex', eligible: true },
    { id: 'codex-two', provider: 'codex', eligible: true },
    { id: 'custom-api', provider: 'codex', eligible: false },
  ],
  quotas: [
    {
      id: 'codex',
      provider: 'codex',
      windows: [{ usedPercent: 0, duration: 18000, resetsAt: null }],
    },
  ],
};
const agentList = {
  kind: 'agent',
  connected: true,
  error: '',
  machinePresence: { state: 'live', onlineMachineIds: ['m1', 'm2'] },
  agentUsage: { m1: subscription, m2: subscription },
};

test('configuration groups stay separate while provider allowances appear once per machine', () => {
  const sections = remoteSettingsSections({
    ...agentList,
    items: [
      codexAgent,
      { ...codexAgent, machineId: 'm2', readOnly: true },
      { ...codexAgent, id: 'codex-two' },
      { ...codexAgent, id: 'custom-api', name: 'Custom API' },
    ],
  });
  const first = sections.find((section) => section.id === 'machine:m1');
  assert.equal(first.rows.length, 3);
  assert.ok(first.rows.every((row) => row.id.startsWith('setting:')));
  const allowances = sections.filter((section) =>
    section.id.endsWith(':usage'),
  );
  assert.equal(allowances.length, 2);
  assert.ok(allowances.every((section) => section.rows.length === 1));
  assert.notEqual(allowances[0].rows[0].id, allowances[1].rows[0].id);
  assert.equal(allowances[0].rows[0].progress, 0);
  assert.ok(
    allowances[0].rows[0].subtitle.includes(t('settings.usage.resetUnknown')),
  );
  assert.ok(allowances[0].footer.includes(t('settings.usage.shared')));
  const second = sections.find((section) => section.id === 'machine:m2');
  assert.equal(second.rows[0].action, false);
  assert.notEqual(first.footer, second.footer);
});

test('unknown presence and failed settings reads label retained Agent data as cached', () => {
  for (const change of [
    { error: 'read failed' },
    { machinePresence: { state: 'unknown', onlineMachineIds: [] } },
    { machinePresence: { state: 'live', onlineMachineIds: [] } },
  ]) {
    const sections = remoteSettingsSections({
      ...agentList,
      ...change,
      items: [codexAgent],
      syncedAt: 1,
      now: 1000,
    });
    const quota = sections.find((section) => section.id.endsWith(':usage'));
    assert.ok(quota.footer.includes(t('settings.usage.cached')));
    assert.ok(!quota.footer.includes(t('settings.usage.shared')));
    assert.equal(quota.rows[0].progress, 0);
    assert.ok(
      !quota.footer.includes(
        t('settings.remote.syncedAt', { time: t('time.justNow') }),
      ),
    );
    if (change.error)
      assert.ok(sections[0].footer.includes(t('settings.remote.agentCached')));
  }
});

test('missing, ineligible and mismatched usage configs never become zero usage', () => {
  for (const config of [
    undefined,
    { ...codexAgent, id: 'custom-api' },
    { ...codexAgent, detail: 'claude' },
  ]) {
    const items = [config ?? codexAgent];
    const agentUsage = config ? agentList.agentUsage : undefined;
    const sections = remoteSettingsSections({
      ...agentList,
      items,
      agentUsage,
    });
    const quota = sections.find((section) => section.id.endsWith(':usage'));
    assert.equal(quota.rows.length, 1);
    assert.equal(quota.rows[0].title, t('settings.usage.empty'));
    assert.equal(quota.rows[0].value, undefined);
    assert.equal(quota.rows[0].progress, undefined);
  }
});
