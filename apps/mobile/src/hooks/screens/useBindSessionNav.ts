import { useEffect } from 'react';
import { present } from '@/lib/presentation';
import { showToast } from '@/ui/toast';
import { subscribeSessionNav } from '@/features/sessions/sessionNav';
import { SessionScreen, type SessionParams } from '@/screens/SessionScreen';
import { CreateSessionScreen } from '@/screens/CreateSessionScreen';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { t } from '../../lib/i18n/index.ts';

export function useBindSessionNav({
  enabled = true,
  openSession,
}: {
  enabled?: boolean;
  openSession?: (params: SessionParams) => void;
} = {}) {
  const { account } = useAuth();
  const { selected } = useCatalog();
  useEffect(() => {
    if (!enabled) return;
    const open = async (params: SessionParams) => {
      if (openSession) openSession(params);
      else
        await present(SessionScreen, params, { title: params.session.title });
    };
    return subscribeSessionNav(async (intent, signal) => {
      try {
        if (intent.kind === 'open') {
          await open({ session: intent.session });
          return;
        }
        if (intent.workspaceId !== selected?.id) return;
        const result = await present(
          CreateSessionScreen,
          {
            workspaceId: intent.workspaceId,
            projects: intent.catalog.projects,
            projectId: intent.projectId,
            context: intent.context,
          },
          openSession
            ? { sheetAllowedDetents: [1], sheetGrabberVisible: false }
            : undefined,
        );
        if (!signal.aborted && result.status === 'completed')
          await open(result.value);
      } catch {
        if (signal.aborted) return;
        showToast(
          t(
            intent.kind === 'open'
              ? 'session.toast.openFailed'
              : 'session.toast.createFailed',
          ),
        );
      }
    });
  }, [enabled, openSession, account?.user.id, selected?.id]);
}
