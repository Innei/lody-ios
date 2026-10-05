import { useCallback, useEffect, useState } from 'react';
import {
  NativeGroupedList,
  NativeNavigationHeader,
  workspaceChanges,
  type WorkspaceChanges,
  type NativeListSection,
} from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import { t, tp } from '@/lib/i18n';
import { basename, dirname } from '@/features/sessions/path';
import { FileDiffScreen } from './FileDiffScreen';

export type WorkspaceChangesParams = {
  sessionId: string;
  source?: typeof workspaceChanges;
};

function View() {
  const { params, push } = usePageRuntime<WorkspaceChangesParams>();
  const colors = usePalette();
  const [result, setResult] = useState<WorkspaceChanges>();
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [revision, setRevision] = useState(0);
  const refresh = useCallback(() => setRevision((value) => value + 1), []);
  useEffect(() => {
    let active = true;
    setLoading(true);
    setError('');
    setResult(undefined);
    (params.source ?? workspaceChanges)({ sessionId: params.sessionId })
      .then((value) => {
        if (!active) return;
        if (value.status === 'unavailable') {
          setError(
            value.reason === 'base_unavailable'
              ? t('diff.reason.baseUnavailable')
              : t('workspaceChanges.error'),
          );
        } else setResult(value);
      })
      .catch(() => {
        if (active) setError(t('workspaceChanges.error'));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [params.sessionId, params.source, revision]);
  const files = result?.status === 'ok' ? result.files : [];
  const sections: NativeListSection[] = [];
  if (result?.status === 'ok') {
    const base =
      result.base === 'diff-store'
        ? t('workspaceChanges.localBase')
        : result.base;
    const hasStats = files.every(
      (file) => file.add != null && file.del != null,
    );
    sections.push({
      id: 'changes',
      header: tp('changes.fileCount', files.length, { count: files.length }),
      headerValue:
        hasStats && files.length
          ? `+${files.reduce((sum, file) => sum + (file.add ?? 0), 0)} −${files.reduce((sum, file) => sum + (file.del ?? 0), 0)}`
          : undefined,
      footer: t('workspaceChanges.base', { base }),
      rows: files.map((file) => {
        const stats =
          file.add != null && file.del != null
            ? [
                { text: `+${file.add}`, tint: 'green' },
                { text: ` −${file.del}`, tint: 'danger' },
              ]
            : undefined;
        return {
          id: `file:${file.path}`,
          title: basename(file.path),
          subtitle: dirname(file.path) || undefined,
          subtitleMono: true,
          filePath: file.path,
          badge: file.kind ? t(`workspaceChanges.${file.kind}`) : undefined,
          valueSegments: stats,
          accessibilityValue: stats?.map((segment) => segment.text).join(''),
          action: true,
          navigates: true,
          disclosure: true,
        };
      }),
    });
  }
  if (error)
    sections.push({
      id: 'error',
      footer: error,
      rows: [{ id: 'retry', title: t('common.retry'), action: true }],
    });
  let placeholder = t('workspaceChanges.empty');
  if (loading) placeholder = t('common.reading');
  else if (error) placeholder = '';
  return (
    <>
      <NativeNavigationHeader
        title={t('workspaceChanges.title')}
        items={[
          {
            type: 'button',
            icon: { type: 'sfSymbol', name: 'arrow.clockwise' },
            accessibilityLabel: t('workspaceChanges.refresh'),
            disabled: loading,
            onPress: refresh,
          },
        ]}
      />
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        sections={sections}
        refreshing={loading}
        onRefresh={refresh}
        placeholder={placeholder}
        onRowPress={({ nativeEvent: { id } }) => {
          if (id === 'retry') {
            refresh();
            return;
          }
          const file = files.find((file) => `file:${file.path}` === id);
          if (!file) return;
          void push(
            FileDiffScreen,
            { sessionId: params.sessionId, path: file.path },
            { title: basename(file.path) },
          );
        }}
      />
    </>
  );
}

export const WorkspaceChangesScreen = definePage<WorkspaceChangesParams>({
  id: 'workspace-changes',
  title: t('workspaceChanges.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from a session');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
