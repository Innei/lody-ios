import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const RemoteSettingsScreen = definePage<{
  kind: 'machine' | 'agent' | 'mcp';
  userId: string;
  workspaceId: string;
}>({
  id: 'remote-settings',
  title: t('settings.remote.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
