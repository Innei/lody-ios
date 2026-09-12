import assert from 'node:assert/strict';
import test from 'node:test';
import { setLocale } from '../../src/lib/i18n/index.ts';
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
    sections.map((section) => section.id),
    ['setting:agent:m1:grok', 'setting:agent:m1:claude'],
  );
  assert.match(sections.at(-1).footer, /更新于/);
  assert.equal(
    remoteSettingsPlaceholder({
      items: [grok],
      loading: true,
      error: '',
    }),
    '',
  );
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
