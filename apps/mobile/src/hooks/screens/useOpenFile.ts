import { useEffect, useRef } from 'react';
import { openFile as nativeOpenFile } from '@lody-ios/kit';

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
      await nativeOpenFile({ sessionId, path, line });
    } finally {
      busy.current = false;
    }
  };
}
