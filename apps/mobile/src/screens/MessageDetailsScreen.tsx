import { useMemo, useSyncExternalStore } from 'react';
import { NativeGroupedList } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { t } from '@/lib/i18n';
import { messageDetailSections } from '@/features/sessions/messageDetails';
import type { createProcessSource } from './ProcessScreen';
import type { EntrySummary } from '@/models/session';

type Params = {
  entryId: string;
  source: ReturnType<typeof createProcessSource>;
};
function View() {
  const { params, cancel } = usePageRuntime<Params>();
  const entriesJSON = useSyncExternalStore(
    params.source.subscribe,
    params.source.getSnapshot,
  );
  const entry = (JSON.parse(entriesJSON) as EntrySummary[]).find(
    (entry) => entry.id === params.entryId,
  );
  const actions = useMemo(
    () => [
      { type: 'button' as const, title: t('common.done'), onPress: cancel },
    ],
    [cancel],
  );
  useSheetHeader(actions);
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      transparent
      onRowPress={() => {}}
      sections={messageDetailSections(entry)}
      placeholder={t('message.details.empty')}
    />
  );
}
export const MessageDetailsScreen = definePage<Params>({
  id: 'message-details',
  title: t('message.details.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from a message');
  },
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [0.75, 1],
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});
