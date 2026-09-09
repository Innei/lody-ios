import assert from 'node:assert/strict';
import test from 'node:test';
import { sessionTitleDetails } from '../../src/features/sessions/sessionTitle.ts';

const session = {
  id: 'new-session',
  machineId: 'm1',
  title: 'First message',
  status: 'idle',
  archived: false,
  pinned: false,
  projectId: 'p1',
  createdAt: '2026-09-09T08:00:00Z',
};

test('new session title details use creation names until catalog catches up', () => {
  const details = sessionTitleDetails(
    { projects: [], sessions: [], machineIds: [] },
    session,
    { projectName: 'Lody iOS', machineName: 'Studio Mac' },
  );

  assert.equal(details.projectName, 'Lody iOS');
  assert.equal(details.machineName, 'Studio Mac');
});

test('catalog names replace creation snapshots after synchronization', () => {
  const project = {
    id: 'p1',
    machineId: 'm1',
    name: 'Renamed project',
    rootPath: '/code/lody-ios',
  };
  const details = sessionTitleDetails(
    {
      projects: [project],
      sessions: [],
      machineIds: ['m1'],
      machineNames: { m1: 'Renamed Mac' },
    },
    session,
    { projectName: 'Old project', machineName: 'Old Mac' },
  );

  assert.equal(details.project, project);
  assert.equal(details.projectName, 'Renamed project');
  assert.equal(details.machineName, 'Renamed Mac');
});
