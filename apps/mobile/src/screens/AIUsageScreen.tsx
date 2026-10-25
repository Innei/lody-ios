import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const AIUsageScreen = definePage({
  id: 'ai-usage',
  title: t('settings.aiUsage.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
