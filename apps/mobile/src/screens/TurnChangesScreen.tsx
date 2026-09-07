import { NativeGroupedList, type NativeListSection } from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { usePalette } from '@/theme/palette';
import type { ChangedFile } from '@/features/sessions/transcript/changes';
import { FileDiffScreen } from '@/screens/FileDiffScreen';
import { basename, dirname } from '@/features/sessions/path';
import { t, tp } from '../i18n/index.ts';

export type TurnChangesParams = {
  sessionId: string;
  entryId: string;
  files: ChangedFile[];
};

function View() {
  const { params, push } = usePageRuntime<TurnChangesParams>();
  const colors = usePalette();
  const add = params.files.reduce((sum, file) => sum + file.add, 0);
  const del = params.files.reduce((sum, file) => sum + file.del, 0);
  const sections: NativeListSection[] = [
    {
      id: 'files',
      header: tp('changes.fileCount', params.files.length, {
        count: params.files.length,
      }),
      headerValue: `+${add} −${del}`,
      rows: params.files.map((file) => ({
        id: file.path,
        title: basename(file.path),
        subtitle: dirname(file.path) || undefined,
        subtitleMono: true,
        badge: file.status,
        diff: { add: file.add, del: file.del },
        action: true,
        navigates: true,
        disclosure: true,
      })),
    },
  ];
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={sections}
      placeholder={t('changes.empty')}
      onRowPress={({ nativeEvent: { id } }) =>
        void push(
          FileDiffScreen,
          { sessionId: params.sessionId, entryId: params.entryId, path: id },
          { title: basename(id) },
        )
      }
    />
  );
}

export const TurnChangesScreen = definePage<TurnChangesParams>({
  id: 'turn-changes',
  title: t('changes.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('请从会话打开');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
