import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export type SessionShareParams = {
  workspaceId: string;
  sessionId: string;
};

export const SessionShareScreen = definePage<SessionShareParams>({
  id: 'session-share',
  title: t('share.title'),
  native: true,
  presentation: { style: 'pageSheet', headerVariant: 'transparent' },
});
