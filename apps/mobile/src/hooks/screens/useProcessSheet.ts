import { useLayoutEffect, useMemo, useRef } from 'react';
import { present } from '@/lib/presentation';
import { t } from '@/lib/i18n/index.ts';
import { createProcessSource, ProcessScreen } from '@/screens/ProcessScreen';

export function useProcessSheet(
  entriesJSON: string,
  onActivityPress: (entryId: string, itemId: string) => void,
  sessionId?: string,
) {
  const source = useMemo(() => createProcessSource(entriesJSON), []);
  const activity = useRef(onActivityPress);
  useLayoutEffect(() => {
    activity.current = onActivityPress;
    source.update(entriesJSON);
  }, [entriesJSON, onActivityPress, source]);
  return (entryId: string, startItemId?: string) =>
    void present(
      ProcessScreen,
      {
        entryId,
        sessionId,
        startItemId,
        source,
        onActivityPress: (entry, item) => activity.current(entry, item),
      },
      startItemId === '__tasks__' ? { title: t('process.tasks') } : undefined,
    );
}
