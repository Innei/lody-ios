import { useMemo, useSyncExternalStore } from 'react';
import { Alert } from 'react-native';
import { NativeGroupedList } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n/index.ts';
import {
  conversationSections,
  type ConversationSheetOptions,
} from '@/features/sessions/conversationSheet';
import type { Session } from '@/models/catalog';
import type { createProcessSource } from './ProcessScreen';

export type ConversationsParams = {
  rootId: string;
  activeId: string;
  source: ReturnType<typeof createProcessSource>;
  create?: ConversationSheetOptions['create'];
  onDelete?: (id: string) => Promise<void>;
};

export type ConversationsResult =
  { type: 'select'; id: string } | { type: 'newTab' } | { type: 'newSideChat' };

function View() {
  const { params, finish } = usePageRuntime<
    ConversationsParams,
    ConversationsResult
  >();
  const colors = usePalette();
  const json = useSyncExternalStore(
    params.source.subscribe,
    params.source.getSnapshot,
  );
  const sessions = useMemo(() => JSON.parse(json) as Session[], [json]);
  const sections = conversationSections(
    sessions,
    params.rootId,
    params.activeId,
    { accent: colors.accent, create: params.create },
  );
  const confirmDelete = (id: string) => {
    const title = sessions.find((session) => session.id === id)?.title ?? '';
    Alert.alert(t('conversations.deleteTitle'), title, [
      { text: t('common.cancel'), style: 'cancel' },
      {
        text: t('conversations.deleteSideChat'),
        style: 'destructive',
        onPress: () =>
          void params
            .onDelete?.(id)
            .catch(() => Alert.alert(t('conversations.deleteFailed'))),
      },
    ]);
  };
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      transparent
      sections={sections}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'new-tab') finish({ type: 'newTab' });
        else if (id === 'new-side-chat') finish({ type: 'newSideChat' });
        else finish({ type: 'select', id });
      }}
      onRowAction={({ nativeEvent }) => {
        if (nativeEvent.actionId === 'delete') confirmDelete(nativeEvent.id);
      }}
    />
  );
}

export const ConversationsScreen = definePage<
  ConversationsParams,
  ConversationsResult
>({
  id: 'session-conversations',
  title: t('conversations.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from the session screen');
  },
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [0.6, 1],
    sheetInitialDetentIndex: 0,
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});
