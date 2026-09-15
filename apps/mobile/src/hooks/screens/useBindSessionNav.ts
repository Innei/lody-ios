import { useEffect } from 'react';
import { cancelComposerRelay, prepareMorphReveal } from '@lody-ios/kit';
import { present, type PagePresentationOptions } from '@/lib/presentation';
import { showToast } from '@/ui/toast';
import { subscribeSessionNav } from '@/features/sessions/sessionNav';
import { SessionScreen, type SessionParams } from '@/screens/SessionScreen';
import { CreateSessionScreen } from '@/screens/CreateSessionScreen';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { t } from '../../lib/i18n/index.ts';
import { prepareSessionHistory } from '@/features/sessions/prepareSessionHistory';

function sheetOptions(
  morphSourceLabel: string | undefined,
  embedded: boolean,
): Partial<PagePresentationOptions> | undefined {
  if (embedded) return { sheetAllowedDetents: [1], sheetGrabberVisible: false };
  if (!morphSourceLabel) return undefined;
  prepareMorphReveal(morphSourceLabel);
  return { animationType: 'none', morphSourceLabel };
}

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
    const open = async (params: SessionParams, preparing = false) => {
      if (openSession) openSession(params);
      else
        await present(SessionScreen, params, {
          title: params.session.title,
          animationType: preparing ? 'none' : 'slide',
        });
    };
    return subscribeSessionNav(async (intent, signal) => {
      let relayId: string | undefined;
      let opening: Promise<void> | undefined;
      const cancelRelay = () => {
        if (relayId) void cancelComposerRelay(relayId);
      };
      signal.addEventListener('abort', cancelRelay, { once: true });
      try {
        if (intent.kind === 'open') {
          const initialHistory = await prepareSessionHistory(
            account?.user.id ?? '',
            selected?.id ?? '',
            intent.session.id,
          );
          if (signal.aborted) return;
          await open({ session: intent.session, initialHistory });
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
            onCreated: (created) => {
              relayId = created.composerRelayId;
              if (signal.aborted) {
                cancelRelay();
                return Promise.reject(new Error('Navigation cancelled'));
              }
              opening = open(created, true);
              return opening;
            },
          },
          sheetOptions(intent.morphSourceLabel, !!openSession),
        );
        if (result.status === 'completed') {
          relayId = result.value.composerRelayId;
          if (!signal.aborted) await (opening ?? open(result.value));
          else cancelRelay();
        } else cancelRelay();
      } catch {
        cancelRelay();
        if (signal.aborted) return;
        showToast(
          t(
            intent.kind === 'open'
              ? 'session.toast.openFailed'
              : 'session.toast.createFailed',
          ),
        );
      } finally {
        signal.removeEventListener('abort', cancelRelay);
      }
    });
  }, [enabled, openSession, account?.user.id, selected?.id]);
}
