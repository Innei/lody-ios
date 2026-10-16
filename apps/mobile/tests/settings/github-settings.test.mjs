import { githubSettingsSchema } from '../../src/models/github-settings.ts';
import assert from 'node:assert/strict';
import test from 'node:test';
import { githubSettingsSections } from '../../src/features/settings/github-settings.ts';
import { setLocale } from '../../src/lib/i18n/index.ts';
setLocale('en');
const data = {
  canManage: false,
  roleKnown: true,
  repositories: [
    {
      repoFullName: 'LodyAI/Lody',
      name: 'Lody',
      repositoryId: 1,
      private: false,
      enabled: true,
    },
  ],
  personal: { enabled: true, authorization: { state: 'expired' } },
  errors: [],
};
test('expired or missing identity cannot offer enabling personal operations, members cannot manage repositories', () => {
  const rows = githubSettingsSections(data, true).flatMap(
    (section) => section.rows,
  );
  assert.equal(
    rows.find((row) => row.id === 'identity').title,
    'Authorization expired',
  );
  assert.deepEqual(
    rows
      .find((row) => row.id === 'preference')
      .options.map((option) => option.id),
    ['disabled'],
  );
  assert.equal(
    rows.find((row) => row.id === 'repo:LodyAI/Lody').options,
    undefined,
  );
  assert.ok(!rows.some((row) => row.id === 'install'));
  const missing = githubSettingsSections(undefined, false).flatMap(
    (section) => section.rows,
  );
  assert.equal(
    missing.find((row) => row.id === 'identity').title,
    'Identity not verified',
  );
  assert.throws(() =>
    githubSettingsSchema.parse({
      ...data,
      personal: { enabled: true, authorization: { state: 'authorized' } },
    }),
  );
  const admin = githubSettingsSections(
    { ...data, canManage: true },
    true,
  ).flatMap((section) => section.rows);
  assert.equal(
    admin.find((row) => row.id === 'repo:LodyAI/Lody').options.length,
    2,
  );
});
