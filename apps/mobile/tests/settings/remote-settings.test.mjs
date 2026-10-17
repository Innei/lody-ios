import assert from 'node:assert/strict';
import test from 'node:test';
import { setLocale, t } from '../../src/lib/i18n/index.ts';
import {
  loadRemoteSettings,
  memoryRemoteSettingsCache,
  parseSavedRemoteSettings,
  remoteSettingsKey,
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
    error: '',
    connected: true,
    agentUsage: usage,
  });
  assert.deepEqual(
    sections.flatMap((section) => section.rows.map((row) => row.id)),
    [],
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
  });
  assert.deepEqual(
    sections.map((group) => group.rows.map((row) => row.id)),
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
  assert.equal(second.rows[0].trailingSymbol, 'lock');
  assert.ok(sections.find((section) => section.id === 'machine:').header);
});

test('agent rows show the name once, with the provider icon instead of a provider subtitle', () => {
  const [section] = remoteSettingsSections({
    kind: 'agent',
    items: [claude],
    error: '',
    connected: true,
  });
  const [row] = section.rows;
  assert.equal(row.title, 'Claude Code');
  assert.equal(row.subtitle, undefined);
  assert.equal(row.imageAsset, 'lody-agent-claude');
  assert.ok(!(section.footer ?? '').includes('m1'));
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
  { kind: 'machine', id: 'build', name: 'Builder', detail: 'Linux' },
];
const machineList = {
  kind: 'machine',
  items: machines,
  error: '',
  connected: true,
  machinePresence: { state: 'live', onlineMachineIds: ['owner-mac'] },
};

test('machine rows carry presence as status and text, never the raw id unless names collide', () => {
  const [section] = remoteSettingsSections(machineList);
  const [owner, teammate, builder] = section.rows;
  assert.equal(owner.status, 'online');
  assert.equal(teammate.status, 'offline');
  assert.equal(owner.subtitle, `${t('devices.online')} · macOS · owner-mac`);
  assert.ok(!builder.subtitle.includes('build'));
  assert.equal(builder.subtitle, `${t('devices.offline')} · Linux`);
  assert.notEqual(owner.id, teammate.id);
  assert.match(teammate.subtitle, /team-mac/);
});

test('read-only machines keep their status text and show a lock instead of a sentence', () => {
  const [section] = remoteSettingsSections(machineList);
  const teammate = section.rows[1];
  assert.equal(teammate.action, false);
  assert.equal(teammate.disclosure, false);
  assert.equal(teammate.trailingSymbol, 'lock');
  assert.ok(teammate.subtitle.includes(t('devices.offline')));
  assert.ok(!teammate.subtitle.includes(t('settings.remote.readOnly')));
  assert.equal(section.footer, t('settings.remote.machineFooter'));
});

test('disconnected or failed machine refresh never presents stale presence as online', () => {
  for (const state of [
    { connected: false },
    { error: 'refresh failed' },
    { machinePresence: { state: 'unknown', onlineMachineIds: [] } },
  ]) {
    const [section] = remoteSettingsSections({ ...machineList, ...state });
    assert.ok(section.rows.every((row) => row.status === 'unknown'));
    assert.ok(
      section.rows.every((row) => row.subtitle.includes(t('devices.unknown'))),
    );
    assert.ok(
      section.rows.every((row) => !row.subtitle.includes(t('devices.online'))),
    );
  }
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

test('each machine is one section whose quota rings appear once per provider above its configurations', () => {
  const sections = remoteSettingsSections({
    ...agentList,
    items: [
      codexAgent,
      { ...codexAgent, machineId: 'm2', readOnly: true },
      { ...codexAgent, id: 'codex-two' },
      { ...codexAgent, id: 'custom-api', name: 'Custom API' },
    ],
  });
  assert.equal(sections.length, 2);
  const first = sections.find((section) => section.id === 'machine:m1');
  assert.equal(first.rows.length, 3);
  assert.equal(first.headerStatus, 'online');
  assert.equal(first.header, `Studio · ${t('devices.online')}`);
  assert.equal(first.visual.type, 'quotas');
  assert.equal(first.visual.items.length, 1);
  assert.equal(first.visual.items[0].fraction, 0);
  assert.equal(first.visual.dimmed, false);
  assert.equal(
    first.footer,
    `${t('settings.usage.paceFooter')}\n${t('settings.usage.sharedShort')}`,
  );
  const second = sections.find((section) => section.id === 'machine:m2');
  assert.notEqual(first.visual.items[0].id, second.visual.items[0].id);
  assert.equal(second.rows[0].action, false);
});

test('offline, unknown or failed reads keep cached rings but dim them and say why', () => {
  for (const [change, footer] of [
    [
      { machinePresence: { state: 'live', onlineMachineIds: [] } },
      'settings.usage.lastOffline',
    ],
    [
      { machinePresence: { state: 'unknown', onlineMachineIds: [] } },
      'settings.usage.lastUnknown',
    ],
    [{ error: 'read failed' }, 'settings.usage.lastUnknown'],
    [{ connected: false }, 'settings.usage.lastUnknown'],
  ]) {
    const [section] = remoteSettingsSections({
      ...agentList,
      ...change,
      items: [codexAgent],
    });
    assert.equal(section.visual.dimmed, true);
    assert.equal(section.visual.items[0].fraction, 0);
    assert.equal(section.visual.items[0].pace, undefined);
    assert.equal(section.visual.items[0].detail, undefined);
    assert.equal(section.visual.items[0].tone, undefined);
    assert.equal(section.footer, t(footer));
    assert.notEqual(section.headerStatus, 'online');
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
    const [section] = remoteSettingsSections({
      ...agentList,
      items,
      agentUsage,
    });
    assert.equal(section.visual, undefined);
  }
  const [offline] = remoteSettingsSections({
    ...agentList,
    machinePresence: { state: 'live', onlineMachineIds: [] },
    items: [codexAgent],
    agentUsage: undefined,
  });
  assert.equal(offline.footer, t('settings.usage.noneOffline'));
});

test('read-only MCP servers show a lock and no read-only sentence', () => {
  const [section] = remoteSettingsSections({
    kind: 'mcp',
    connected: true,
    error: '',
    items: [
      {
        kind: 'mcp',
        id: 'a',
        name: 'github',
        machineName: 'Studio',
        enabledByDefault: true,
      },
      {
        kind: 'mcp',
        id: 'b',
        name: 'sentry',
        machineName: 'Studio',
        readOnly: true,
      },
    ],
  });
  assert.equal(section.rows[0].value, t('settings.mcp.defaultOn'));
  assert.equal(section.rows[1].trailingSymbol, 'lock');
  assert.ok(!section.rows[1].subtitle.includes(t('settings.mcp.readOnly')));
  assert.equal(section.footer, t('settings.remote.mcpHint'));
});
