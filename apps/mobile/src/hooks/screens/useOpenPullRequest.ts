import { useEffect, useRef } from 'react';
import { Alert, Linking, Share } from 'react-native';
import type { PullRequestReference } from '@/models/pull-request';
import type { PullRequestSource } from '@/features/pull-request/source';
import { livePullRequest } from '@/cloud/github/pullRequests';
import { PullRequestScreen } from '@/screens/PullRequestScreen';
import { usePageRuntime } from './usePageRuntime';
import { t } from '@/lib/i18n';

export function useOpenPullRequest(
  workspaceId: string,
  userId: string,
  appendDraft: (text: string) => boolean,
) {
  const { push } = usePageRuntime();
  const open = useRef(false);
  const sources = useRef(new Set<PullRequestSource>());
  const scope = `${userId}:${workspaceId}`;
  const currentScope = useRef(scope);
  currentScope.current = scope;
  const append = useRef(appendDraft);
  append.current = appendDraft;
  useEffect(() => {
    currentScope.current = scope;
    return () => {
      for (const source of sources.current) source.dispose();
      sources.current.clear();
      currentScope.current = '';
    };
  }, [scope]);
  return async (reference: PullRequestReference) => {
    if (!workspaceId || !userId || open.current) return;
    open.current = true;
    const source = livePullRequest(workspaceId, reference);
    sources.current.add(source);
    const valid = () => currentScope.current === scope;
    function openGitHub(url = reference.url) {
      if (!valid()) return;
      // Check URLs are external data. Only open GitHub HTTPS links here.
      if (!/^https:\/\/github\.com\//i.test(url)) url = reference.url;
      void Linking.openURL(url).catch(() =>
        Alert.alert(t('pr.github'), t('pr.error.unavailable')),
      );
    }
    try {
      await push(
        PullRequestScreen,
        {
          source,
          actions: {
            openGitHub,
            share: () => {
              if (valid())
                void Share.share({ url: reference.url }).catch(() => {});
            },
            comment: async (body) => {
              if (!valid()) throw new Error('unauthorized');
              await source.postComment(body);
              return true;
            },
            investigate: (check, checkSha) => {
              if (!valid()) return;
              const lines = [t('pr.investigatePrompt'), reference.url];
              const sha = checkSha ?? source.getSnapshot().data?.headSha;
              if (sha) lines.push(`Commit: ${sha}`);
              if (check)
                lines.push(
                  `${check.name}: ${check.conclusion ?? check.status}`,
                  check.htmlUrl ?? '',
                );
              if (append.current(lines.filter(Boolean).join('\n')))
                Alert.alert(t('pr.investigate'), t('pr.draftAdded'));
            },
          },
        },
        { title: `PR #${reference.number}` },
      );
    } finally {
      source.dispose();
      sources.current.delete(source);
      open.current = false;
    }
  };
}
