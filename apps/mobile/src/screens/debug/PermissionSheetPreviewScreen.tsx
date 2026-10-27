import { definePage } from '@/lib/presentation';
import type { PermissionResult } from '@lody/cloud-runtime/models/session';
import { t } from '@/lib/i18n';

export const PermissionSheetPreviewScreen = definePage<
  { scenario: 'waiting' | 'questions' | 'permission' },
  PermissionResult
>({
  id: 'permission-sheet-preview',
  title: t('permission.title'),
  native: true,
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [0.6, 1],
    sheetInitialDetentIndex: 0,
    sheetGrabberVisible: false,
    dismissible: false,
    headerVariant: 'transparent',
  },
});
