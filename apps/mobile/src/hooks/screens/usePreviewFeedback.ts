import { useRef } from 'react';
import { createSendId } from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { getConnection } from '@/cloud/catalog/connection';
import { getPendingSendStore } from '@/cloud/send/pendingSends';
import { localGeneration } from '@/cloud/kv';
import { sendPreviewFeedback } from '@/features/files/previewFeedback';
import { requestOpenSession } from '@/features/sessions/sessionNav';

export function usePreviewFeedback(sessionId: string) {
  const { account } = useAuth();
  const { selected, catalog } = useCatalog();
  const scope = `${account?.user.id ?? ''}:${selected?.id ?? ''}:${localGeneration()}`;
  const initialScope = useRef(scope);
  const current = useRef(scope);
  current.current = scope;
  const session = catalog.sessions.find((item) => item.id === sessionId);
  return {
    send: async (text: string) => {
      if (
        !account ||
        !selected ||
        !session ||
        current.current !== initialScope.current
      )
        throw new Error('unavailable');
      return sendPreviewFeedback({
        store: getPendingSendStore(account.user.id, selected.id),
        session,
        text,
        id: createSendId(),
        connected: getConnection().state === 'live',
      });
    },
    openSession: () => {
      if (session && current.current === initialScope.current)
        void requestOpenSession(session);
    },
  };
}
