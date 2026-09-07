import { useLayoutEffect, useMemo, useRef } from 'react';
import { present } from '@/presentation';
import { createProcessSource, ProcessScreen } from '@/screens/ProcessScreen';

export function useProcessSheet(
  entriesJSON: string,
  onActivityPress: (entryId: string, itemId: string) => void,
) {
  const source = useMemo(() => createProcessSource(entriesJSON), []);
  const activity = useRef(onActivityPress);
  useLayoutEffect(() => {
    activity.current = onActivityPress;
    source.update(entriesJSON);
  }, [entriesJSON, onActivityPress, source]);
  return (entryId: string, startItemId?: string) =>
    void present(ProcessScreen, {
      entryId,
      startItemId,
      source,
      onActivityPress: (entry, item) => activity.current(entry, item),
    });
}
