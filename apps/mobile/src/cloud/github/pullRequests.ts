import { githubPullRequest } from '@lody-ios/kit';
import type {
  PullRequestPreviewData,
  PullRequestReference,
} from '@/models/pull-request';
import { createPullRequestSource } from '@/features/pull-request/source';

export function livePullRequest(
  workspaceId: string,
  reference: PullRequestReference,
) {
  const target = {
    workspaceId,
    repository: reference.repository,
    number: reference.number,
  };
  return createPullRequestSource(
    async () =>
      JSON.parse(
        await githubPullRequest(
          JSON.stringify({ ...target, operation: 'read' }),
        ),
      ) as PullRequestPreviewData,
    async (body) => {
      await githubPullRequest(
        JSON.stringify({ ...target, operation: 'comment', body }),
      );
    },
  );
}
