import { definePage } from '@/lib/presentation';

export const DiagnosticsPreviewScreen = definePage({
  id: 'diagnostics-preview',
  title: 'Diagnostics',
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
