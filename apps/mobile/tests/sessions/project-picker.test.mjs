import assert from 'node:assert/strict';
import test from 'node:test';
import { setLocale } from '../../src/lib/i18n/index.ts';
import {
  filterPickerProjects,
  githubPickerStatusRows,
  projectPickerSearchPlaceholder,
  projectPickerSegment,
  projectPickerSegments,
  projectPickerSections,
  splitPickerProjects,
} from '../../src/features/sessions/projectPicker.ts';

setLocale('en');

const local = {
  id: 'ui:local:alpha',
  name: 'Alpha',
  machineId: 'ui',
  rootPath: '/tmp/alpha',
};
const github = {
  id: 'github:Owner/Repo1',
  name: 'Owner/Repo1',
  machineId: '',
  rootPath: '',
};
const localRow = { id: local.id, title: local.name, action: true };
const githubRow = { id: github.id, title: github.name, action: true };

test('opens on local unless the current selection is a GitHub repository', () => {
  assert.equal(projectPickerSegment('ui:local:alpha'), 0);
  assert.equal(projectPickerSegment('github:Owner/Repo1'), 1);
});

test('keeps catalog local projects separate from fetched GitHub repositories', () => {
  const split = splitPickerProjects([local, github], [github]);
  assert.deepEqual(
    split.local.map((project) => project.id),
    [local.id],
  );
  assert.deepEqual(
    split.github.map((project) => project.id),
    [github.id],
  );
});

test('uses catalog GitHub projects until the workspace list arrives', () => {
  const split = splitPickerProjects([local, github]);
  assert.deepEqual(
    split.github.map((project) => project.id),
    [github.id],
  );
});

test('local and GitHub occupy separate segments without repeating the section title', () => {
  const localSection = projectPickerSections({
    segment: 0,
    localRows: [localRow],
    githubRows: [githubRow],
    githubEmpty: false,
  });
  const githubSection = projectPickerSections({
    segment: 1,
    localRows: [localRow],
    githubRows: [githubRow],
    githubEmpty: false,
  });
  assert.deepEqual(projectPickerSegments(), [
    'Local projects',
    'GitHub repositories',
  ]);
  assert.equal(localSection.length, 1);
  assert.equal(localSection[0].id, 'local');
  assert.equal(localSection[0].header, undefined);
  assert.deepEqual(
    localSection[0].rows.map((row) => row.id),
    [local.id],
  );
  assert.equal(githubSection.length, 1);
  assert.equal(githubSection[0].id, 'github');
  assert.equal(githubSection[0].header, undefined);
  assert.deepEqual(
    githubSection[0].rows.map((row) => row.id),
    [github.id],
  );
});

test('search matches name, path and id without regard to case', () => {
  const beta = {
    id: 'ui:local:beta',
    name: 'Beta',
    machineId: 'ui',
    rootPath: '/tmp/studio',
  };
  assert.deepEqual(
    filterPickerProjects([local, beta, github], '').map(
      (project) => project.id,
    ),
    [local.id, beta.id, github.id],
  );
  assert.deepEqual(
    filterPickerProjects([local, beta, github], '  ALPHA ').map(
      (project) => project.id,
    ),
    [local.id],
  );
  assert.deepEqual(
    filterPickerProjects([local, beta, github], 'studio').map(
      (project) => project.id,
    ),
    [beta.id],
  );
  assert.deepEqual(
    filterPickerProjects([local, beta, github], 'owner/repo1').map(
      (project) => project.id,
    ),
    [github.id],
  );
  assert.deepEqual(filterPickerProjects([local, beta, github], 'zzz'), []);
});

test('search placeholder names the active project type', () => {
  assert.equal(projectPickerSearchPlaceholder(0), 'Search local projects');
  assert.equal(projectPickerSearchPlaceholder(1), 'Search GitHub repositories');
});

test('GitHub empty and load failure stay on the GitHub segment', () => {
  assert.deepEqual(
    githubPickerStatusRows({ loaded: true, failed: false, empty: false }),
    [],
  );
  assert.equal(
    githubPickerStatusRows({ loaded: false, failed: false, empty: true })[0].id,
    'github-retry',
  );
  assert.equal(
    githubPickerStatusRows({ loaded: false, failed: true, empty: true })[0]
      .action,
    true,
  );
  assert.equal(
    githubPickerStatusRows({ loaded: true, failed: false, empty: true })[0].id,
    'github-empty',
  );
  assert.equal(
    projectPickerSections({
      segment: 1,
      localRows: [localRow],
      githubRows: githubPickerStatusRows({
        loaded: true,
        failed: false,
        empty: true,
      }),
      githubEmpty: true,
    })[0].footer,
    "Connect a repository in Lody Cloud's integration settings first.",
  );
});
