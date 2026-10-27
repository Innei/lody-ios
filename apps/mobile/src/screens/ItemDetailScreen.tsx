import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export type ItemDetailParams = {
  sessionId: string;
  entryId: string;
  itemIds: string[];
  generation: number;
};

export const ItemDetailScreen = definePage<ItemDetailParams>({
  id: 'session-item-detail',
  panel: true,
  title: t('detail.title'),
  native: true,
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [0.6, 1],
    sheetInitialDetentIndex: 0,
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});
