import { Stack } from 'expo-router';
import { PlatformColor } from 'react-native';
import {
  NativeGroupedList,
  NativeSymbolButton,
  type NativeListSection,
} from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import { PullRequestCommentScreen } from './PullRequestCommentScreen';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import type { PullRequestActions } from '@/models/pull-request';
import type { PullRequestSource } from '@/features/pull-request/source';
import { usePullRequestSource } from '@/hooks/screens/usePullRequestSource';
import { pullRequestError } from '@/features/pull-request/errors';
import { PullRequestChecksScreen } from './PullRequestChecksScreen';
import { t } from '@/lib/i18n';
import { checksSummary, failedCheck } from '@/features/pull-request/checks';

const stateIcons = {
  open: { imageAsset: 'lody-git-pull-request', imageTint: 'blue' },
  merged: { imageAsset: 'lody-git-merge', imageTint: 'purple' },
  closed: { imageAsset: 'lody-git-pull-request-closed', imageTint: 'danger' },
  draft: { imageAsset: 'lody-git-pull-request-draft', imageTint: 'secondary' },
} as const;

export type PullRequestParams = {
  source: PullRequestSource;
  actions: PullRequestActions;
};

function View() {
  const {
    params: { source, actions },
    push,
  } = usePageRuntime<PullRequestParams>();
  const { data, loading, error } = usePullRequestSource(source);
  const failed = data?.checks.filter(failedCheck).length ?? 0;
  const summary = data ? checksSummary(data) : 'unavailable';
  const sections: NativeListSection[] = [];
  if (!data || error)
    sections.push({
      id: 'load-state',
      rows: [
        {
          id: 'pr-retry',
          title: error ? pullRequestError(error) : t('pr.loading'),
          subtitle: error ? t('pr.retry') : undefined,
          action: !!error,
        },
      ],
      footer: data ? t('pr.stale') : undefined,
    });
  if (data) {
    const emptyComment = data.commentsError
      ? pullRequestError(data.commentsError)
      : t('pr.noComments');
    sections.push(
      {
        id: 'identity',
        header: data.repository,
        rows: [
          {
            id: 'pr-title',
            title: data.title,
            subtitle: [t(`pr.state.${data.state}`), data.author]
              .filter(Boolean)
              .join(' · '),
            ...stateIcons[data.state],
          },
        ],
        footer: `${data.headRef} → ${data.baseRef}`,
      },
      {
        id: 'summary',
        rows: [
          {
            id: 'pr-checks',
            title: t('pr.checks'),
            value:
              summary === 'failed'
                ? t('pr.failedCount', { count: failed })
                : t(`pr.summary.${summary}`),
            image:
              summary === 'passed'
                ? 'checkmark.circle'
                : 'exclamationmark.circle',
            imageTint: summary === 'failed' ? 'warning' : 'secondary',
            action: true,
            disclosure: true,
            navigates: true,
          },
          {
            id: 'pr-files',
            title: t('pr.files'),
            valueSegments: [
              { text: `${data.changedFiles} · ` },
              { text: `+${data.additions}`, tint: 'blue' },
              { text: ` −${data.deletions}`, tint: 'danger' },
            ],
            image: 'doc.text',
          },
          {
            id: 'pr-commits',
            title: t('pr.commits'),
            value: String(data.commits),
            imageAsset: 'lody-git-commit',
          },
        ],
        footer: t('pr.head', { sha: data.headSha.slice(0, 7) }),
      },
      {
        id: 'description',
        header: t('pr.description'),
        rows: [
          {
            id: 'pr-body',
            title: data.body || t('pr.noDescription'),
          },
        ],
      },
      {
        id: 'activity',
        header: t('pr.activity'),
        footer: data.commentsTruncated
          ? t('pr.moreComments')
          : t('pr.commentsScope'),
        rows: data.comments.length
          ? data.comments.map((comment) => ({
              id: `pr-comment-${comment.id}`,
              title: comment.body || '—',
              subtitle: comment.author,
            }))
          : [
              {
                id: 'pr-empty-comments',
                title: emptyComment,
                image: 'bubble.left',
              },
            ],
      },
    );
  }
  return (
    <>
      <Stack.Toolbar placement="right">
        <Stack.Toolbar.Button
          icon="arrow.clockwise"
          accessibilityLabel={t('pr.refresh')}
          disabled={loading}
          onPress={() => void source.refresh()}
        />
        <Stack.Toolbar.Menu
          icon="ellipsis"
          accessibilityLabel={t('common.more')}
        >
          <Stack.Toolbar.MenuAction
            icon="square.and.arrow.up"
            onPress={actions.share}
          >
            {t('pr.share')}
          </Stack.Toolbar.MenuAction>
        </Stack.Toolbar.Menu>
      </Stack.Toolbar>
      <NativeGroupedList
        style={{ flex: 1 }}
        sections={sections}
        onRowPress={({ nativeEvent: { id } }) => {
          if (id === 'pr-retry') void source.refresh();
          if (id === 'pr-checks' && data)
            void push(PullRequestChecksScreen, { source, actions });
        }}
      />
      <Stack.Toolbar placement="bottom">
        <Stack.Toolbar.View>
          <NativeSymbolButton
            accessibilityName={t('pr.github')}
            imageAsset="lody-mark-github"
            tint="blue"
            style={{ width: 44, height: 44 }}
            onPress={() => actions.openGitHub()}
          />
        </Stack.Toolbar.View>
        <Stack.Toolbar.Spacer />
        <Stack.Toolbar.Button
          tintColor={PlatformColor('systemBlue')}
          disabled={!data || !!error}
          onPress={() =>
            data &&
            void present(PullRequestCommentScreen, {
              repository: data.repository,
              number: data.number,
              onSubmit: actions.comment,
            })
          }
        >
          {t('pr.comment')}
        </Stack.Toolbar.Button>
      </Stack.Toolbar>
    </>
  );
}

export const PullRequestScreen = definePage<PullRequestParams>({
  id: 'pull-request',
  title: 'PR',
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from a session');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
