import { t } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';

export const DiagnosticsScreen = definePage({
  id: 'diagnostics',
  title: t('diagnostics.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
