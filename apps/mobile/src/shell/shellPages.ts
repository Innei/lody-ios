import type { Session } from '@lody/cloud-runtime/models/catalog';
import { getCatalogStore } from '@/cloud/catalog/store';
import { shareSession } from '@/features/sessions/sessionActions';
import {
  requestNewSession,
  requestOpenSession,
} from '@/features/sessions/sessionNav';
import {
  registerShellPages,
  registerShellSessionHandler,
} from '@/lib/presentation/shellNavigation';
import { DebugScreen } from '@/screens/debug/DebugScreen';
import { NotificationSettingsScreen } from '@/screens/NotificationSettingsScreen';
import { ProjectScreen } from '@/screens/ProjectScreen';

registerShellPages([DebugScreen, NotificationSettingsScreen, ProjectScreen]);

registerShellSessionHandler((intent) => {
  if (intent.action === 'open') {
    if (intent.session)
      void requestOpenSession(JSON.parse(intent.session) as Session);
    return;
  }
  if (intent.action === 'share') {
    if (intent.sessionId)
      shareSession({ id: intent.workspaceId, slug: null }, intent.sessionId);
    return;
  }
  const { catalog, pendingSessions } = getCatalogStore();
  void requestNewSession(
    intent.workspaceId,
    { ...catalog, sessions: [...catalog.sessions, ...pendingSessions] },
    intent.projectId,
    intent.context,
    intent.zoomSourceLabel,
  );
});
