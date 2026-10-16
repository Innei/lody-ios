import { workspaceSettingsRaw } from '@lody-ios/kit';
import {
  visibilitySchema,
  type VisibilityService,
} from '@/models/project-visibility';
export const requestVisibility: VisibilityService = async (request) =>
  visibilitySchema.parse(
    JSON.parse(await workspaceSettingsRaw(JSON.stringify(request))),
  );

import {
  githubSettingsSchema,
  type GitHubSettingsService,
} from '@/models/github-settings';
export const requestGitHubSettings: GitHubSettingsService = async (request) => {
  const result = JSON.parse(
    await workspaceSettingsRaw(JSON.stringify(request)),
  );
  if (request.action === 'install') {
    const url = new URL(result.url);
    if (
      url.origin !== 'https://github.com' ||
      url.username ||
      url.password ||
      url.hash ||
      url.pathname !== '/apps/lodyai/installations/new' ||
      !url.searchParams.get('state')
    )
      throw new Error('invalid_installation');
    return { url: url.href };
  }
  return githubSettingsSchema.parse(result);
};
