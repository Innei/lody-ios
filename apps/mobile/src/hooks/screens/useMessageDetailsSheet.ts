import { useLayoutEffect, useMemo } from 'react';
import { present } from '@/lib/presentation';
import { createProcessSource } from '@/screens/ProcessScreen';
import { MessageDetailsScreen } from '@/screens/MessageDetailsScreen';

export function useMessageDetailsSheet(entriesJSON: string) {
  const source = useMemo(() => createProcessSource(entriesJSON), []);
  useLayoutEffect(() => source.update(entriesJSON), [source, entriesJSON]);
  return (entryId: string) =>
    void present(MessageDetailsScreen, { source, entryId });
}
