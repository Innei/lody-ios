import { registerShellPages } from '@/lib/presentation/shellNavigation';
import { ArchivedSessionsScreen } from '@/screens/ArchivedSessionsScreen';
import { DebugScreen } from '@/screens/debug/DebugScreen';
import { DiagnosticsScreen } from '@/screens/DiagnosticsScreen';
import { NotificationSettingsScreen } from '@/screens/NotificationSettingsScreen';
import { ProjectHistoryScreen } from '@/screens/ProjectHistoryScreen';
import { RemoteSettingsScreen } from '@/screens/RemoteSettingsScreen';
import { WorkspaceEditorScreen } from '@/screens/WorkspaceEditorScreen';

registerShellPages([
  ArchivedSessionsScreen,
  DebugScreen,
  DiagnosticsScreen,
  NotificationSettingsScreen,
  ProjectHistoryScreen,
  RemoteSettingsScreen,
  WorkspaceEditorScreen,
]);
