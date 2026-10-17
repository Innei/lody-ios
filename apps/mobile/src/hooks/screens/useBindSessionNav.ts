import { useEffect } from 'react';
import { cancelComposerRelay, prepareSheetZoom } from '@lody-ios/kit';
import { present, type PagePresentationOptions } from '@/lib/presentation';
import { homeScope, showHomeSession } from '@/lib/presentation/homeDetail';
import { getLayoutMode } from '@/lib/presentation/layoutMode';
import { showToast } from '@/ui/toast';
import { subscribeSessionNav } from '@/features/sessions/sessionNav';
import { SessionScreen, type SessionParams } from '@/screens/SessionScreen';
import { CreateSessionScreen } from '@/screens/CreateSessionScreen';
import { SessionShareScreen } from '@/screens/SessionShareScreen';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { t } from '../../lib/i18n/index.ts';
import { prepareSessionHistory } from '@/features/sessions/prepareSessionHistory';

function sheetOptions(
  zoomSourceLabel: string | undefined,
  embedded: boolean,
): Partial<PagePresentationOptions> | undefined {
  if (embedded) return { sheetAllowedDetents: [1], sheetGrabberVisible: false };
  if (!zoomSourceLabel) return undefined;
  prepareSheetZoom(zoomSourceLabel);
  return { animationType: 'slide', zoomSourceLabel };
}

export function useBindSessionNav() {
  const { account } = useAuth();
  const { selected } = useCatalog();
  useEffect(() => {
    const scope = homeScope(account?.user.id, selected?.id);
    const open = (params: SessionParams, preparing = false) =>
      showHomeSession(params, scope, (value) =>
        present(SessionScreen, value, {
          title: value.session.title,
          animationType: preparing ? 'none' : 'slide',
        }),
      );
    return subscribeSessionNav(async (intent, signal) => {
      let relayId: string | undefined;
      let opening: Promise<unknown> | undefined;
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
          await open({
            session: intent.session,
            initialHistory,
            findQuery: intent.findQuery,
          });
          return;
        }
        if (intent.workspaceId !== selected?.id) return;
        if (intent.kind === 'share') {
          await present(SessionShareScreen, {
            workspaceId: intent.workspaceId,
            sessionId: intent.sessionId,
          });
          return;
        }
        const result = await present(
          CreateSessionScreen,
          {
            workspaceId: intent.workspaceId,
            projects: intent.catalog.projects,
            projectId: intent.projectId,
            context: intent.context,
            initialText: intent.draft?.text,
            initialAttachmentsJSON: intent.draft?.attachmentsJSON,
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
          sheetOptions(intent.zoomSourceLabel, getLayoutMode() !== 'compact'),
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
  }, [account?.user.id, selected?.id]);
}
