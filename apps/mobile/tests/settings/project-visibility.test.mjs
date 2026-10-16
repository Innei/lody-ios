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
