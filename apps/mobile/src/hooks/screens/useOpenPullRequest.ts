import { useCallback, useRef } from 'react';
import type { PullRequestReference } from '@lody/cloud-runtime/models/pull-request';
import { PullRequestScreen } from '@/screens/PullRequestScreen';
import { usePageRuntime } from './usePageRuntime';

export function useOpenPullRequest(
  workspaceId: string,
  userId: string,
  appendDraft: (text: string) => boolean,
) {
  const { push } = usePageRuntime();
  const open = useRef(false);
  const current = useRef({ workspaceId, userId, appendDraft });
  current.current = { workspaceId, userId, appendDraft };
  return useCallback(
    async (reference: PullRequestReference) => {
      if (!workspaceId || !userId || open.current) return;
      open.current = true;
      try {
        await push(
          PullRequestScreen,
          {
            workspaceId,
            userId,
            repository: reference.repository,
            number: reference.number,
            onInvestigate: (text) => {
              const scope = current.current;
              if (
                scope.workspaceId !== workspaceId ||
                scope.userId !== userId ||
                !scope.appendDraft(text)
              )
                throw new Error('unavailable');
            },
          },
          { title: `PR #${reference.number}` },
        );
      } finally {
        open.current = false;
      }
    },
    [push, workspaceId, userId],
  );
}
