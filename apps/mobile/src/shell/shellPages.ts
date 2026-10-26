import type { Catalog, Session } from '@lody/cloud-runtime/models/catalog';
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
import { SettingsScreen } from '@/screens/SettingsScreen';
import { WorkspaceEditorScreen } from '@/screens/WorkspaceEditorScreen';

registerShellPages([
  DebugScreen,
  NotificationSettingsScreen,
  ProjectScreen,
  SettingsScreen,
  WorkspaceEditorScreen,
]);

let creating = false;

registerShellSessionHandler((intent) => {
  if (intent.action === 'open') {
    if (intent.session)
      void requestOpenSession(
        JSON.parse(intent.session) as Session,
        intent.findQuery,
      );
    return;
  }
  if (intent.action === 'share') {
    if (intent.sessionId)
      shareSession({ id: intent.workspaceId, slug: null }, intent.sessionId);
    return;
  }
  if (creating) return;
  creating = true;
  const { catalog, pendingSessions } = getCatalogStore();
  // UI Verify fixtures publish their own catalog; the live store is empty there.
  const source = intent.catalog
    ? (JSON.parse(intent.catalog) as Catalog)
    : { ...catalog, sessions: [...catalog.sessions, ...pendingSessions] };
  void requestNewSession(
    intent.workspaceId,
    source,
    intent.projectId,
    intent.context,
    intent.zoomSourceLabel,
  ).finally(() => {
    creating = false;
  });
});
