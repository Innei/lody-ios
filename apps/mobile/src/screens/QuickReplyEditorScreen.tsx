import type { QuickReply } from '@lody/cloud-runtime/models/settings';
import { t } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';

export const QuickReplyEditorScreen = definePage<{ item?: QuickReply }>({
  id: 'quick-reply-editor',
  title: t('settings.quickReplies.edit'),
  native: true,
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
