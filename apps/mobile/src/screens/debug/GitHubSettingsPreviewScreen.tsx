import { useMemo } from 'react';
import { definePage } from '@/lib/presentation';
import type {
  GitHubSettings,
  GitHubSettingsService,
} from '@/features/settings/github-settings';
import { GitHubSettingsView } from '../GitHubSettingsScreen';
function Preview() {
  const service = useMemo<GitHubSettingsService>(() => {
    let first = true,
      failWrite = true;
    const data: GitHubSettings = {
      canManage: true,
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
      personal: {
        enabled: true,
        authorization: { state: 'expired', githubAccountId: 'fixture' },
      },
      errors: [],
    };
    return async (request) => {
      if (first) {
        first = false;
        throw new Error('fixture-load');
      }
      if (request.action === 'install')
        return {
          url: 'https://github.com/apps/lodyai/installations/new?state=offline-fixture',
        };
      if (request.action === 'repository') {
        if (failWrite) {
          failWrite = false;
          throw new Error('fixture-write');
        }
        data.repositories![0].enabled = request.enabled;
      }
      if (request.action === 'preference')
        data.personal!.enabled = request.enabled;
      return JSON.parse(JSON.stringify(data)) as GitHubSettings;
    };
  }, []);
  return (
    <GitHubSettingsView
      workspaceId="github-fixture"
      service={service}
      openURL={async () => {}}
    />
  );
}
export const GitHubSettingsPreviewScreen = definePage({
  id: 'github-settings-preview',
  title: 'GitHub',
  Component: Preview,
  presentation: { headerVariant: 'transparent' },
});
