import { useLayoutEffect, useMemo, useRef, useSyncExternalStore } from 'react';
import { NativeChat } from '@lody-ios/kit';
import { definePage, present, usePageRuntime } from '@/presentation';
import { t } from '../../../i18n/index.ts';

type ProcessParams = {
  entryId: string;
  startItemId?: string;
  source: ReturnType<typeof createSource>;
  onActivityPress: (entryId: string, itemId: string) => void;
};

// The owning session keeps its one runtime subscription. A presented page reads
// the same projection; dismissing it never unwatches the underlying session.
function createSource(initial: string) {
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

export function useProcessSheet(
  entriesJSON: string,
  onActivityPress: ProcessParams['onActivityPress'],
) {
  const source = useMemo(() => createSource(entriesJSON), []);
  const activity = useRef(onActivityPress);
  useLayoutEffect(() => {
    activity.current = onActivityPress;
    source.update(entriesJSON);
  }, [entriesJSON, onActivityPress, source]);
  return (entryId: string, startItemId?: string) =>
    void present(processPage, {
      entryId,
      startItemId,
      source,
      onActivityPress: (entry, item) => activity.current(entry, item),
    });
}

function ProcessScreen() {
  const { params } = usePageRuntime<ProcessParams>();
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
      onReconnect={() => {}}
    />
  );
}

const processPage = definePage<ProcessParams>({
  id: 'session-process',
  title: t('process.title'),
  Component: ProcessScreen,
  parseRouteParams: () => {
    throw new Error('请从会话页打开');
  },
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [0.6, 1],
    sheetInitialDetentIndex: 0,
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});
