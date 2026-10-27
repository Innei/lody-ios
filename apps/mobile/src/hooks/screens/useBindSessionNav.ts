import { useEffect } from 'react';
import { navigateSession } from '@lody-ios/kit';
import { subscribeSessionNav } from '@/features/sessions/sessionNav';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { showToast } from '@/ui/toast';
import { t } from '@/lib/i18n';

export function useBindSessionNav() {
  const { account } = useAuth();
  const { selected } = useCatalog();
  useEffect(
    () =>
      subscribeSessionNav(async (intent, signal) => {
        if (signal.aborted) return;
        try {
          await navigateSession({
            userId: account?.user.id,
            workspaceId: selected?.id,
            ...intent,
          });
        } catch {
          if (!signal.aborted)
            showToast(
              t(
                intent.kind === 'create'
                  ? 'session.toast.createFailed'
                  : 'session.toast.openFailed',
              ),
            );
        }
      }),
    [account?.user.id, selected?.id],
  );
}
