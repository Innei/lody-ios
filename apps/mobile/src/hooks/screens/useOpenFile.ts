import { useEffect, useRef } from 'react';
import { openFile as nativeOpenFile } from '@lody-ios/kit';
import { present } from '@/lib/presentation';

export function useOpenFile(sessionId: string) {
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
      if (!active.current) return;
      if (await nativeOpenFile({ sessionId, path, line })) return;
      if (!active.current) return;
      const { FileContentScreen } = await import('@/screens/FileContentScreen');
      if (!active.current) return;
      await present(FileContentScreen, { sessionId, path, line });
    } finally {
      busy.current = false;
    }
  };
}
