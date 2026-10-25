import { t } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';

export const AgentRolesScreen = definePage({
  id: 'agent-roles',
  title: t('settings.roles.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
