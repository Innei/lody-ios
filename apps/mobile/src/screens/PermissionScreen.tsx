import { definePage } from '@/lib/presentation';
import type { PermissionResult } from '@lody/cloud-runtime/models/session';
import { t } from '@/lib/i18n';

export type PermissionParams = { sessionId: string };

export const PermissionScreen = definePage<PermissionParams, PermissionResult>({
  id: 'session-permission',
  title: t('permission.title'),
  native: true,
  presentation: {
    style: 'formSheet',
    // The shell's sheets take fixed detents; `fitToContents` would open full height.
    sheetAllowedDetents: [0.6, 1],
    sheetInitialDetentIndex: 0,
    sheetGrabberVisible: false,
    // Answering is the way out; the header close button is the escape hatch.
    dismissible: false,
    headerVariant: 'transparent',
  },
});
