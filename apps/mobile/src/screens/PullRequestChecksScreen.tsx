import { Stack } from 'expo-router';
import { PlatformColor } from 'react-native';
import { NativeGroupedList } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import {
  checkState,
  checkSymbols,
  failedCheck,
} from '@/features/pull-request/checks';
import type {
  PullRequestCheck,
  PullRequestActions,
} from '@/models/pull-request';
import type { PullRequestSource } from '@/features/pull-request/source';
import { usePullRequestSource } from '@/hooks/screens/usePullRequestSource';
import { pullRequestError } from '@/features/pull-request/errors';
import { PullRequestCheckScreen } from './PullRequestCheckScreen';
import { t } from '@/lib/i18n';

function View() {
  const {
    params: { source, actions },
    push,
  } = usePageRuntime<{
    source: PullRequestSource;
    actions: PullRequestActions;
  }>();
  const { data, loading, error } = usePullRequestSource(source);
  const checks = data?.checks ?? [];
  let notice = t('pr.summary.empty');
  if (data?.checksTruncated) notice = t('pr.summary.partial');
  if (error || data?.checksError)
    notice = pullRequestError(error ?? data!.checksError!);
  const groups = [
    {
      id: 'failed',
      title: t('pr.failed'),
      checks: checks.filter(failedCheck),
    },
    {
      id: 'active',
      title: t('pr.active'),
      checks: checks.filter((c) => c.status !== 'completed'),
    },
    {
      id: 'completed',
      title: t('pr.completed'),
      checks: checks.filter((c) => c.status === 'completed' && !failedCheck(c)),
    },
  ];
  function row(check: PullRequestCheck) {
    const state = checkState(check);
    return {
      id: `pr-check-${check.id}`,
      title: check.name,
      subtitle: [t(`pr.check.${state}`), check.appName]
        .filter(Boolean)
        .join(' · '),
      image: checkSymbols[state],
      imageTint: failedCheck(check) ? 'danger' : 'secondary',
      action: true,
      disclosure: true,
      navigates: true,
    };
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
      </Stack.Toolbar>
      <NativeGroupedList
        style={{ flex: 1 }}
        sections={[
          {
            id: 'commit',
            footer: data
              ? `${data.repository} · #${data.number}\n${t('pr.head', { sha: data.headSha.slice(0, 7) })}`
              : undefined,
            rows: [],
          },
          ...(!checks.length ||
          error ||
          data?.checksError ||
          data?.checksTruncated
            ? [
                {
                  id: 'check-notice',
                  rows: [{ id: 'pr-checks-notice', title: notice }],
                },
              ]
            : []),
          ...groups
            .filter((g) => g.checks.length)
            .map((g) => ({
              id: g.id,
              header: `${g.title} · ${g.checks.length}`,
              rows: g.checks.map(row),
            })),
        ]}
        onRowPress={({ nativeEvent: { id } }) => {
          const check = checks.find((c) => `pr-check-${c.id}` === id);
          if (check && data)
            void push(
              PullRequestCheckScreen,
              { check, sha: data.headSha, source, actions },
              { title: check.name },
            );
        }}
      />
      <Stack.Toolbar placement="bottom">
        <Stack.Toolbar.Button
          onPress={() => actions.openGitHub()}
          tintColor={PlatformColor('systemBlue')}
        >
          {t('pr.github')}
        </Stack.Toolbar.Button>
        <Stack.Toolbar.Spacer />
        <Stack.Toolbar.Button
          onPress={() => actions.investigate()}
          tintColor={PlatformColor('systemBlue')}
        >
          {t('pr.investigate')}
        </Stack.Toolbar.Button>
      </Stack.Toolbar>
    </>
  );
}
export const PullRequestChecksScreen = definePage<{
  source: PullRequestSource;
  actions: PullRequestActions;
}>({
  id: 'pull-request-checks',
  title: t('pr.checks'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from a pull request');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
