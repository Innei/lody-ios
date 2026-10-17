import assert from 'node:assert/strict';
import test from 'node:test';
import { listState } from '../../src/features/settings/list-state.ts';
import { setLocale, t } from '../../src/lib/i18n/index.ts';

setLocale('en');

const base = { title: 'Couldn’t Load Machines', hasData: false };

test('first load without data shows only the skeleton', () => {
  const state = listState({ ...base, loading: true });
  assert.equal(state.loading, true);
  assert.equal(state.notice, undefined);
  assert.equal(state.unavailable, undefined);
});

test('a refresh over existing data never shows the skeleton', () => {
  const state = listState({ ...base, hasData: true, loading: true });
  assert.equal(state.loading, false);
  assert.equal(state.notice, undefined);
});

test('a failed load with nothing to show becomes the unavailable page', () => {
  const state = listState({ ...base, failed: true });
  assert.equal(state.loading, false);
  assert.equal(state.unavailable.title, base.title);
  assert.equal(state.unavailable.actionTitle, t('settings.state.tryAgain'));
  assert.equal(state.notice, undefined);
});

test('a failed refresh keeps data and explains its age in a notice', () => {
  const state = listState({
    ...base,
    hasData: true,
    failed: true,
    syncedAt: Date.parse('2026-10-17T10:00:00'),
    now: Date.parse('2026-10-17T12:00:00'),
  });
  assert.equal(state.unavailable, undefined);
  assert.equal(
    state.notice.text,
    t('settings.state.staleAt', {
      time: t('time.hoursAgo.other', { count: 2 }),
    }),
  );
  assert.equal(state.notice.actionSymbol, 'arrow.clockwise');
});

test('an unconfirmed write outranks a stale or offline notice and only offers a re-read', () => {
  const state = listState({
    ...base,
    hasData: true,
    failed: true,
    offline: true,
    unconfirmed: true,
  });
  assert.equal(state.notice.text, t('settings.state.unconfirmed'));
  assert.equal(state.notice.actionLabel, t('settings.state.refresh'));
});

test('offline data with a successful read says status is unavailable', () => {
  const state = listState({ ...base, hasData: true, offline: true });
  assert.equal(state.notice.text, t('settings.state.offline'));
});

test('partial results surface as a notice, never as the unavailable page', () => {
  const state = listState({ ...base, partial: t('settings.aiUsage.partial') });
  assert.equal(state.unavailable, undefined);
  assert.equal(state.notice.text, t('settings.aiUsage.partial'));
});
