import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const MessageDetailsScreen = definePage<{
  entryId: string;
  entriesJSON: string;
}>({
  id: 'message-details',
  panel: true,
  title: t('message.details.title'),
  native: true,
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [0.75, 1],
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});
