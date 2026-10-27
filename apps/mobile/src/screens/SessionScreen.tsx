import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';
import type { Session } from '@lody/cloud-runtime/models/catalog';

export type SessionParams = {
  session: Session;
  findQuery?: string;
  modelId?: string;
  effort?: string;
  modeId?: string;
};

export const SessionScreen = definePage<SessionParams>({
  id: 'session',
  native: true,
  title: t('session.title'),
  presentation: { style: 'push', headerVariant: 'transparent' },
});
