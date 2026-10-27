import { registerShellPages } from '@/lib/presentation/shellNavigation';
import { AgentErrorScreen } from '@/screens/AgentErrorScreen';
import { DebugScreen } from '@/screens/debug/DebugScreen';
import { EditMessageScreen } from '@/screens/EditMessageScreen';
import { FileContentScreen } from '@/screens/FileContentScreen';
import { FileDiffScreen } from '@/screens/FileDiffScreen';
import { FilesScreen } from '@/screens/FilesScreen';
import { ItemDetailScreen } from '@/screens/ItemDetailScreen';
import { MessageDetailsScreen } from '@/screens/MessageDetailsScreen';
import { MessageShareScreen } from '@/screens/MessageShareScreen';
import { NotificationSettingsScreen } from '@/screens/NotificationSettingsScreen';
import { ProjectScreen } from '@/screens/ProjectScreen';
import { SettingsScreen } from '@/screens/SettingsScreen';
import { WorkspaceEditorScreen } from '@/screens/WorkspaceEditorScreen';
import { WorkspaceChangesScreen } from '@/screens/WorkspaceChangesScreen';

registerShellPages([
  AgentErrorScreen,
  DebugScreen,
  EditMessageScreen,
  FileContentScreen,
  FileDiffScreen,
  FilesScreen,
  ItemDetailScreen,
  MessageDetailsScreen,
  MessageShareScreen,
  NotificationSettingsScreen,
  ProjectScreen,
  SettingsScreen,
  WorkspaceChangesScreen,
  WorkspaceEditorScreen,
]);
