import { useEffect } from 'react';
import { present } from '@/presentation';
import { showToast } from '@/ui/toast';
import { subscribeSessionNav } from '@/features/sessions/sessionNav';
import { sessionPage } from '@/features/sessions/SessionScreen';
import { createSessionPage } from '@/features/sessions/CreateSessionScreen';
import { t } from '../../i18n/index.ts';

export function useBindSessionNav() {
  useEffect(() => {
    return subscribeSessionNav(async (intent) => {
      try {
        if (intent.kind === 'open') {
          await present(
            sessionPage,
            { session: intent.session },
            { title: intent.session.title },
          );
          return;
        }
        const result = await present(createSessionPage, {
          workspaceId: intent.workspaceId,
          projects: intent.catalog.projects,
          projectId: intent.projectId,
        });
        if (result.status === 'completed')
          await present(
            sessionPage,
            {
              session: result.value.session,
              modelId: result.value.modelId,
              effort: result.value.effort,
              modeId: result.value.modeId,
            },
            { title: result.value.session.title },
          );
      } catch {
        showToast(
          t(
            intent.kind === 'open'
              ? 'session.toast.openFailed'
              : 'session.toast.createFailed',
          ),
        );
      }
    });
  }, []);
}
