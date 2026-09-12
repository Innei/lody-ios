import assert from 'node:assert/strict';
import test from 'node:test';
import { Flock } from '@loro-dev/flock-wasm/base64';
import { projectRows } from '../../src/cloud/catalog/model.ts';
import {
  inboxSections,
  projectSections,
  searchSections,
  sessionRow,
} from '../../src/features/sessions/inbox.ts';
import { setLocale } from '../../src/lib/i18n/index.ts';

test('catalog model changes reach every session row without loading a transcript', () => {
  setLocale('zh-Hans');
  const flock = new Flock('session-model');
  flock.set(['e', 'session-s1'], true);
  flock.set(['m', 'session-s1'], {
    id: 's1',
    machineId: 'm1',
    title: 'Session',
    status: 'completed',
    createdAt: '2026-09-12T00:00:00Z',
    project: { kind: 'local', localProjectId: 'p1' },
    branchName: 'feature/worktree',
    lastModel: {
      name: ' GPT-6 ',
      modelId: 'gpt-6',
      _meta: { private: 'not-projected' },
    },
  });
  const read = () => projectRows(flock.scan(), 'meta');
  const data = read();
  assert.deepEqual(data.sessions[0].lastModel, {
    name: 'GPT-6',
    modelId: 'gpt-6',
  });
  const rows = [
    inboxSections(data, { accent: 'blue' })[0].rows[0],
    projectSections(data, 'blue')[0].rows[1],
    searchSections(data, 'Session', 'blue')[0].rows[0],
    sessionRow(data.sessions[0], 'blue'),
  ];
  for (const row of rows) {
    assert.equal(row.modelName, 'GPT-6');
    assert.ok(row.subtitle.endsWith('feature/worktree'));
  }
  flock.set(['m', 'session-s1', 'lastModel'], { modelId: 'actual-id-only' });
  assert.equal(
    sessionRow(read().sessions[0], 'blue').modelName,
    'actual-id-only',
  );
  flock.set(['m', 'session-s1', 'lastModel'], null);
  assert.equal(sessionRow(read().sessions[0], 'blue').modelName, '尚未运行');
  flock.set(['m', 'session-s1', 'lastModel'], { name: 42 });
  assert.equal(sessionRow(read().sessions[0], 'blue').modelName, '');
  const legacy = {
    ...data.sessions[0],
    branchName: undefined,
    lastModel: undefined,
  };
  assert.equal(sessionRow(legacy, 'blue').modelName, '');
  assert.equal(sessionRow(legacy, 'blue').subtitle, '');
});
