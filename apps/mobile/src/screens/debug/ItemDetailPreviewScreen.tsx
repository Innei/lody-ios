import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const ItemDetailPreviewScreen = definePage<{
  scenario: 'diff' | 'subtask' | 'paging';
}>({
  id: 'item-detail-preview',
  title: t('detail.title'),
  native: true,
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [0.6, 1],
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});
