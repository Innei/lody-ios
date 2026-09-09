import { useOpenFile } from '@/hooks/screens/useOpenFile';
import { useSyncExternalStore } from 'react';
import { NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { t } from '../lib/i18n/index.ts';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

type ProcessParams = {
  sessionId?: string;
  entryId: string;
  startItemId?: string;
  source: ReturnType<typeof createProcessSource>;
  onActivityPress: (entryId: string, itemId: string) => void;
};

// The owning session keeps its one runtime subscription. A presented page reads
// the same projection; dismissing it never unwatches the underlying session.
export function createProcessSource(initial: string) {
  let value = initial;
  const listeners = new Set<() => void>();
  return {
    getSnapshot: () => value,
    subscribe: (listener: () => void) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    update: (next: string) => {
      if (value === next) return;
      value = next;
      listeners.forEach((listener) => listener());
    },
  };
}

function View() {
  const { params } = usePageRuntime<ProcessParams>();
  const openFile = useOpenFile(params.sessionId ?? '');
  const entriesJSON = useSyncExternalStore(
    params.source.subscribe,
    params.source.getSnapshot,
  );
  return (
    <NativeChat
      style={{ flex: 1 }}
      entriesJSON={entriesJSON}
      processEntryId={params.entryId}
      processStartId={params.startItemId}
      composerJSON="{}"
      clearDraftToken={0}
      emptyText={t('process.empty')}
      onSend={() => {}}
      onActivityPress={({ nativeEvent }) =>
        params.onActivityPress(nativeEvent.entryId, nativeEvent.itemId)
      }
      onFilePress={({ nativeEvent }) =>
        void openFile(nativeEvent.path, nativeEvent.line)
      }
      onReconnect={() => {}}
    />
  );
}

export const ProcessScreen = definePage<ProcessParams>({
  id: 'session-process',
  title: t('process.title'),
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
