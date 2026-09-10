import { useEffect, useRef } from 'react';
import { basename } from '@/features/sessions/path';
import { usePageRuntime } from './usePageRuntime';

export function useOpenFile(sessionId: string) {
  const { push } = usePageRuntime();
  const busy = useRef(false);
  const active = useRef(true);
  useEffect(() => {
    active.current = true;
    return () => {
      active.current = false;
    };
  }, [sessionId]);
  return async (path: string, line?: number) => {
    if (busy.current || !sessionId) return;
    busy.current = true;
    try {
      const { FileScreen } = await import('@/screens/FileScreen');
      if (!active.current) return;
      await push(
        FileScreen,
        { path, sessionId, line },
        { title: basename(path) },
      );
    } finally {
      busy.current = false;
    }
  };
}
