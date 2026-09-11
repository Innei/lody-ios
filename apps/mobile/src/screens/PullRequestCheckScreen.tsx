import { Stack } from 'expo-router';
import { PlatformColor } from 'react-native';
import { NativeGroupedList } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { checkState, checkSymbols } from '@/features/pull-request/checks';
import type {
  PullRequestCheck,
  PullRequestActions,
} from '@/models/pull-request';
import { t } from '@/lib/i18n';
import type { PullRequestSource } from '@/features/pull-request/source';
import { usePullRequestSource } from '@/hooks/screens/usePullRequestSource';
import { pullRequestError } from '@/features/pull-request/errors';

type Params = {
  check: PullRequestCheck;
  sha: string;
  actions: PullRequestActions;
  source: PullRequestSource;
};
function View() {
  const {
    params: { check: originalCheck, sha, source, actions },
  } = usePageRuntime<Params>();
  const { data, error } = usePullRequestSource(source);
  // Never relabel a previous commit's run with the new head SHA.
  const check =
    data?.headSha === sha
      ? (data.checks.find((c) => c.id === originalCheck.id) ?? originalCheck)
      : originalCheck;
  const state = checkState(check);
  const previousHead = data?.headSha !== sha ? t('pr.previousHead') : undefined;
  return (
    <>
      <NativeGroupedList
        style={{ flex: 1 }}
        sections={[
          ...(!data || error || data.checksError
            ? [
                {
                  id: 'check-error',
                  rows: [
                    {
                      id: 'pr-check-error',
                      title: pullRequestError(
                        error ?? data?.checksError ?? 'unavailable',
                      ),
                    },
                  ],
                },
              ]
            : []),
          ...(data
            ? [
                {
                  id: 'check-state',
                  rows: [
                    {
                      id: 'pr-check-detail',
                      title: check.name,
                      subtitle: check.appName ?? undefined,
                      value: t(`pr.check.${state}`),
                      image: checkSymbols[state],
                      imageTint: 'secondary',
                    },
                  ],
                  footer: [t('pr.head', { sha: sha.slice(0, 7) }), previousHead]
                    .filter(Boolean)
                    .join('\n'),
                },
              ]
            : []),
          {
            id: 'check-output',
            header: t('pr.details'),
            rows: [{ id: 'pr-check-limit', title: t('pr.logsHint') }],
          },
        ]}
        onRowPress={() => {}}
      />
      <Stack.Toolbar placement="bottom">
        <Stack.Toolbar.Button
          onPress={() => actions.openGitHub(check.htmlUrl ?? undefined)}
          tintColor={PlatformColor('systemBlue')}
        >
          {t('pr.github')}
        </Stack.Toolbar.Button>
        <Stack.Toolbar.Spacer />
        <Stack.Toolbar.Button
          disabled={!data}
          onPress={() => actions.investigate(check, sha)}
          tintColor={PlatformColor('systemBlue')}
        >
          {t('pr.investigate')}
        </Stack.Toolbar.Button>
      </Stack.Toolbar>
    </>
  );
}
export const PullRequestCheckScreen = definePage<Params>({
  id: 'pull-request-check',
  title: t('pr.details'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from checks');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
