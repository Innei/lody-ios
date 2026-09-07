import assert from 'node:assert/strict';
import test from 'node:test';
import { relativeTime } from '../src/ui/time.ts';
import {
  agentName,
  sessionState,
  stateSubtitle,
  stateSymbol,
  stateTint,
} from '../src/features/sessions/status.ts';
import { setLocale } from '../src/i18n/index.ts';

setLocale('zh-Hans');

const ACCENT = '#3B4FD9';
const now = Date.parse('2026-09-06T15:00:00+08:00');
const at = (iso) => relativeTime(iso, now);

test('relative time degrades from minutes to a calendar date', () => {
  assert.equal(at('2026-09-06T14:59:30+08:00'), '刚刚');
  assert.equal(at('2026-09-06T14:57:00+08:00'), '3 分钟前');
  assert.equal(at('2026-09-06T11:00:00+08:00'), '4 小时前');
  assert.equal(at('2026-09-05T23:00:00+08:00'), '昨天');
  assert.equal(at('2026-09-02T10:00:00+08:00'), '9月2日');
  assert.equal(at('not a date'), '');
});

test('archived overrides the backend status', () => {
  assert.equal(sessionState('running', true), 'archived');
  assert.equal(sessionState('running'), 'live');
  assert.equal(sessionState('anything-unknown'), 'idle');
});

test('server status types and the awaiting flag map to list states', () => {
  assert.equal(sessionState('requestPermission'), 'attention');
  assert.equal(sessionState('initializing'), 'live');
  assert.equal(sessionState('idle', false, true), 'attention');
  assert.equal(sessionState('running', false, true), 'live');
  assert.equal(relativeTime(now - 3 * 60_000, now), '3 分钟前');
  assert.equal(agentName('claude'), 'Claude Code');
  assert.equal(agentName('custom-agent'), 'custom-agent');
});

test('accent carries only the live state', () => {
  assert.equal(stateTint('live', ACCENT), ACCENT);
  for (const state of ['attention', 'failed', 'idle', 'done', 'archived']) {
    assert.notEqual(stateTint(state, ACCENT), ACCENT);
  }
});

test('every state has a distinct symbol, not just a distinct color', () => {
  const symbols = Object.values(stateSymbol);
  assert.equal(new Set(symbols).size, symbols.length);
});

test('completed rows drop the state word, the checkmark already says it', () => {
  assert.equal(stateSubtitle('done', 'lody-ios', '昨天'), 'lody-ios · 昨天');
  assert.equal(
    stateSubtitle('attention', 'lody-ios', '刚刚'),
    '等待确认 · lody-ios · 刚刚',
  );
  assert.equal(stateSubtitle('live', 'lody-ios', ''), '进行中 · lody-ios');
});
