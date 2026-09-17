import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { LoroDoc, LoroMap } from 'loro-crdt';

const directory = mkdtempSync(join(tmpdir(), 'lody-native-interop-'));
const input = join(directory, 'js.bin');
const output = join(directory, 'native.bin');
const doc = new LoroDoc();
const entry = doc.getList('history').pushContainer(new LoroMap());
entry.set('id', 'existing-turn');
entry.set('text', 'Existing 历史 👋');
doc.commit();
writeFileSync(input, doc.export({ mode: 'snapshot' }));
const run = spawnSync(process.argv[2], [input, output], { stdio: 'inherit' });
assert.equal(run.status, 0);
const update = readFileSync(output);
doc.import(update);
doc.import(update); // Duplicate transport delivery must not duplicate the turn.
const history = doc.toJSON().history;
assert.equal(history.length, 2);
assert.equal(history[0].text, 'Existing 历史 👋');
assert.equal(history[1].id, 'native-turn');
assert.equal(history[1].items[0].text, 'Native 分享 👋');
assert.equal(history[1].inputConfig.agentType, 'grok');
assert.equal(history[1].status, 'pending');
assert.equal(history[1].finished, true);
console.log(
  'PASS: JS 1.15.1 → native Loro → JS, nested text/config, incremental merge and duplicate import',
);
