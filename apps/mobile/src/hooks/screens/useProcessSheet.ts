import { useLayoutEffect, useMemo, useRef } from 'react';
import { usePageRuntime } from './usePageRuntime';
import { t } from '@/lib/i18n/index.ts';
import {
  createProcessSource,
  ProcessScreen,
} from '@/screens/debug/ProcessScreen';
import { openSubagentTask } from './openSubagentTask';
import { findSessionItem } from '@/features/sessions/subagentHistory';

export function useProcessSheet(
  entriesJSON: string,
  onActivityPress: (entryId: string, itemId: string) => void,
  sessionId?: string,
) {
  const { present } = usePageRuntime();
  const source = useMemo(() => createProcessSource(entriesJSON), []);
  const activity = useRef(onActivityPress);
  useLayoutEffect(() => {
    activity.current = onActivityPress;
    source.update(entriesJSON);
  }, [entriesJSON, onActivityPress, source]);
  const onPress = (entry: string, item: string) =>
    activity.current(entry, item);
  const openProcess = (entryId: string, startItemId?: string) =>
    void present(
      ProcessScreen,
      {
        entryId,
        sessionId,
        startItemId,
        source,
        onActivityPress: onPress,
      },
      startItemId === '__tasks__' ? { title: t('process.tasks') } : undefined,
    );
  const openTask = (entryId: string, itemId: string) =>
    openSubagentTask(
      findSessionItem(JSON.parse(source.getSnapshot()), entryId, itemId),
      { source, entryId, sessionId, onActivityPress: onPress },
      present,
    );
  return { openProcess, openTask };
}
