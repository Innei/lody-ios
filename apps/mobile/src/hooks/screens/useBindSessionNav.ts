import { useEffect } from 'react';
import { present } from '@/lib/presentation';
import { showToast } from '@/ui/toast';
import { subscribeSessionNav } from '@/features/sessions/sessionNav';
import { SessionScreen } from '@/screens/SessionScreen';
import { CreateSessionScreen } from '@/screens/CreateSessionScreen';
import { t } from '../../lib/i18n/index.ts';

export function useBindSessionNav() {
  useEffect(() => {
    return subscribeSessionNav(async (intent) => {
      try {
        if (intent.kind === 'open') {
          await present(
            SessionScreen,
            { session: intent.session },
            { title: intent.session.title },
          );
          return;
        }
        const result = await present(CreateSessionScreen, {
          workspaceId: intent.workspaceId,
          projects: intent.catalog.projects,
          projectId: intent.projectId,
          context: intent.context,
        });
        if (result.status === 'completed')
          await present(
            SessionScreen,
            {
              session: result.value.session,
              projectName: result.value.projectName,
              machineName: result.value.machineName,
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
