import type { NativeListSection } from '@lody-ios/kit';
import { t } from '../../lib/i18n/index.ts';
import {
  type GitHubSettings,
  type GitHubSettingsRequest,
  type GitHubSettingsService,
} from '../../models/github-settings.ts';
export type {
  GitHubSettings,
  GitHubSettingsRequest,
  GitHubSettingsService,
} from '../../models/github-settings.ts';
export function githubSettingsSections(
  value: GitHubSettings | undefined,
  enabled: boolean,
): NativeListSection[] {
  let personalTitle = t('settings.github.unknown');
  const personal = value?.personal;
  if (personal)
    personalTitle = t(`settings.github.${personal.authorization.state}`);
  const personalRows: NativeListSection['rows'] = [
    {
      id: 'identity',
      title: personalTitle,
      subtitle:
        personal?.authorization.state === 'authorized'
          ? personal.authorization.profile?.login
          : undefined,
      image: 'person.crop.circle',
    },
  ];
  const personalOptions = [
    {
      id: 'disabled',
      title: t('settings.remote.disabled'),
      selected: !personal?.enabled,
    },
  ];
  if (personal?.authorization.state === 'authorized')
    personalOptions.push({
      id: 'enabled',
      title: t('settings.remote.enabled'),
      selected: personal.enabled,
    });
  if (personal)
    personalRows.push({
      id: 'preference',
      title: t('settings.github.personalPreference'),
      accessibilityValue: t(
        personal.enabled
          ? 'settings.remote.enabled'
          : 'settings.remote.disabled',
      ),
      value: t(
        personal.enabled
          ? 'settings.remote.enabled'
          : 'settings.remote.disabled',
      ),
      action: enabled,
      options: personalOptions,
    });
  let repositoryHint = t('settings.github.roleUnknown');
  if (value?.roleKnown)
    repositoryHint = t(
      value.canManage
        ? 'settings.github.repositoryHint'
        : 'settings.github.readonly',
    );
  return [
    {
      id: 'personal',
      header: t('settings.github.personal'),
      footer: t('settings.github.personalHint'),
      rows: personalRows,
    },
    {
      id: 'repositories',
      header: t('settings.github.repositories'),
      footer: repositoryHint,
      rows: (value?.repositories ?? []).map((repo) => ({
        id: `repo:${repo.repoFullName}`,
        title: repo.repoFullName,
        subtitle: t(
          repo.private ? 'settings.github.private' : 'settings.github.public',
        ),
        accessibilityValue: t(
          repo.enabled ? 'settings.remote.enabled' : 'settings.remote.disabled',
        ),
        value: t(
          repo.enabled ? 'settings.remote.enabled' : 'settings.remote.disabled',
        ),
        action: enabled && value?.canManage,
        options: value?.canManage
          ? [
              {
                id: 'enabled',
                title: t('settings.remote.enabled'),
                selected: repo.enabled,
              },
              {
                id: 'disabled',
                title: t('settings.remote.disabled'),
                selected: !repo.enabled,
              },
            ]
          : undefined,
      })),
    },
    ...(value && value.repositories === null
      ? [
          {
            id: 'repositories-unavailable',
            rows: [
              {
                id: 'repo-unavailable',
                title: t('settings.github.repoUnavailable'),
              },
            ],
          },
        ]
      : []),
    ...(value?.repositories?.length === 0
      ? [
          {
            id: 'no-repositories',
            footer: t('settings.github.empty'),
            rows: [],
          },
        ]
      : []),
    ...(value?.canManage
      ? [
          {
            id: 'installation',
            footer: t('settings.github.browserHint'),
            rows: [
              {
                id: 'install',
                title: t('settings.github.manageApp'),
                image: 'safari',
                action: enabled,
              },
            ],
          },
        ]
      : []),
  ];
}
