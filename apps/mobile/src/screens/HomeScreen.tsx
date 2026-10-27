import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const HomeScreen = definePage({
  id: 'home',
  native: true,
  title: t('tabs.sessions'),
  presentation: { style: 'push', headerShown: false },
});
