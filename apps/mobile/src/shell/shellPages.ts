import { registerShellPages } from '@/lib/presentation/shellNavigation';
import { ArchivedSessionsScreen } from '@/screens/ArchivedSessionsScreen';
import { DebugScreen } from '@/screens/debug/DebugScreen';
import { NotificationSettingsScreen } from '@/screens/NotificationSettingsScreen';
import { ProjectHistoryScreen } from '@/screens/ProjectHistoryScreen';
import { WorkspaceEditorScreen } from '@/screens/WorkspaceEditorScreen';

registerShellPages([
  ArchivedSessionsScreen,
  DebugScreen,
  NotificationSettingsScreen,
  ProjectHistoryScreen,
  WorkspaceEditorScreen,
]);
