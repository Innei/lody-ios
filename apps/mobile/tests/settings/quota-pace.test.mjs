import assert from 'node:assert/strict';
import test from 'node:test';
import { agentUsageRings } from '../../src/features/settings/agent-usage.ts';
import { setLocale, t } from '../../src/lib/i18n/index.ts';

setLocale('en');

const hour = 3600;
const now = Date.parse('2026-10-17T12:00:00Z');
const item = { kind: 'agent', id: 'a', machineId: 'm', detail: 'codex' };
const usage = (window) => ({
  configs: [{ id: 'a', provider: 'codex', eligible: true }],
  quotas: [{ id: 'codex', provider: 'codex', windows: [window] }],
});
const quota = (window) => agentUsageRings(item, usage(window), now)[0];

test('quotas lead with what is left and count down to the reset', () => {
  const q = quota({
    usedPercent: 42,
    duration: 5 * hour,
    resetsAt: now / 1000 + 2 * hour + 14 * 60,
  });
  assert.equal(q.value, t('settings.usage.left', { percent: 58 }));
  assert.equal(q.caption, t('settings.usage.resetsIn', { time: '2h 14m' }));
  assert.equal(q.fraction, 0.42);
  assert.ok(Math.abs(q.pace - (1 - (2 * 3600 + 14 * 60) / (5 * 3600))) < 1e-9);
  assert.equal(q.detail, t('settings.usage.onPace'));
  assert.equal(q.tone, undefined);
});

test('usage ahead of the elapsed window that runs out before reset is a warning', () => {
  const q = quota({
    usedPercent: 17,
    duration: 7 * 24 * hour,
    resetsAt: now / 1000 + 6 * 24 * hour + 6 * hour,
  });
  assert.equal(q.tone, 'warning');
  assert.equal(
    q.detail,
    t('settings.usage.ahead', { percent: 6, time: '3d 16h' }),
  );
  assert.equal(q.caption, t('settings.usage.resetsIn', { time: '6d 6h' }));
});

test('usage within two points of the marker is still on pace', () => {
  const q = quota({
    usedPercent: 51,
    duration: 10 * hour,
    resetsAt: now / 1000 + 5 * hour,
  });
  assert.equal(q.tone, undefined);
  assert.equal(q.detail, t('settings.usage.onPace'));
});

test('an exhausted window only waits for the reset', () => {
  const q = quota({
    usedPercent: 100,
    duration: 5 * hour,
    resetsAt: now / 1000 + 65 * 60,
  });
  assert.equal(q.value, t('settings.usage.left', { percent: 0 }));
  assert.equal(q.detail, t('settings.usage.exhausted'));
  assert.equal(q.tone, 'warning');
  assert.equal(q.caption, t('settings.usage.resetsIn', { time: '1h 5m' }));
});

test('without a reset time there is no pace marker or forecast', () => {
  const q = quota({ usedPercent: 8, duration: 7 * 24 * hour, resetsAt: null });
  assert.equal(q.pace, undefined);
  assert.equal(q.detail, undefined);
  assert.equal(q.caption, t('settings.usage.resetsUnknown'));
});

test('a reset time already in the past never forecasts', () => {
  const q = quota({
    usedPercent: 30,
    duration: 5 * hour,
    resetsAt: now / 1000 - 60,
  });
  assert.equal(q.pace, undefined);
  assert.equal(q.detail, undefined);
});
