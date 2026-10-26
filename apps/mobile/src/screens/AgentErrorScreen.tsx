import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n/index.ts';
import type { SystemNoticeMeta } from '@lody/cloud-runtime/models/session';

export const AgentErrorScreen = definePage<SystemNoticeMeta>({
  id: 'agent-error',
  title: t('native.chat.error.detail'),
  native: true,
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [0.6, 1],
    sheetInitialDetentIndex: 0,
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});
