import { visibilitySchema } from '../../src/models/project-visibility.ts';
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  visibilitySections,
  visibilityId,
} from '../../src/features/settings/project-visibility.ts';
const snapshot = {
  userId: 'owner',
  rows: [
    {
      machineId: 'm1',
      localProjectId: 'same',
      ownerUserId: 'owner',
      sharedWithTeam: false,
      updatedAt: 1,
    },
    {
      machineId: 'm2',
      localProjectId: 'same',
      ownerUserId: 'teammate',
      sharedWithTeam: true,
      updatedAt: 1,
    },
  ],
};
const catalog = {
  projects: [
    { id: 'm1:local:same', machineId: 'm1', name: 'First', rootPath: '/first' },
    {
      id: 'm2:local:same',
      machineId: 'm2',
      name: 'Second',
      rootPath: '/second',
    },
    {
      id: 'm1:local:unknown',
      machineId: 'm1',
      name: 'Unknown',
      rootPath: '/unknown',
    },
  ],
  sessions: [],
  machineIds: [],
};
test('matching local IDs stay machine scoped, foreign and unknown registrations cannot be changed', () => {
  const sections = visibilitySections(snapshot, catalog, true),
    rows = sections.flatMap((section) => section.rows);
  const own = rows.find((row) => row.id === visibilityId(snapshot.rows[0]));
  const foreign = rows.find((row) => row.id === visibilityId(snapshot.rows[1]));
  assert.equal(own.title, 'First');
  assert.equal(own.options.length, 2);
  assert.equal(foreign.title, 'Second');
  assert.equal(foreign.options, undefined);
  assert.equal(rows.find((row) => row.title === 'Unknown').options, undefined);
  assert.ok(
    visibilitySections(snapshot, catalog, false)
      .flatMap((section) => section.rows)
      .every((row) => !row.action),
  );
  assert.throws(() =>
    visibilitySchema.parse({
      userId: 'owner',
      rows: [{ ...snapshot.rows[0], sharedWithTeam: null }],
    }),
  );
});

test('rows show visibility as a symbol and label, sections show machine status instead of raw ids', () => {
  const presence = { state: 'live', onlineMachineIds: ['m1'] };
  const sections = visibilitySections(snapshot, catalog, true, presence);
  const first = sections.find((section) => section.id === 'm1');
  assert.equal(first.footer, undefined);
  assert.equal(first.headerStatus, 'online');
  assert.equal(
    sections.find((section) => section.id === 'm2').headerStatus,
    'offline',
  );
  const rows = sections.flatMap((section) => section.rows);
  const own = rows.find((row) => row.id === visibilityId(snapshot.rows[0]));
  assert.equal(own.valueSymbol, 'lock');
  assert.equal(own.subtitle, '/first');
  assert.equal(own.subtitleMono, true);
  assert.equal(own.image, 'folder');
  const foreign = rows.find((row) => row.id === visibilityId(snapshot.rows[1]));
  assert.equal(foreign.valueSymbol, 'person.2');
  assert.equal(foreign.action, false);
  assert.ok(!foreign.subtitle.includes('/second'));
  const unknown = rows.find((row) => row.title === 'Unknown');
  assert.equal(unknown.valueSymbol, 'questionmark.circle');
  const unknownHeader = visibilitySections(snapshot, catalog, true).find(
    (s) => s.id === 'm1',
  );
  assert.equal(unknownHeader.headerStatus, undefined);
  assert.equal(unknownHeader.header, 'm1');
  assert.match(first.header, / · /);
});
