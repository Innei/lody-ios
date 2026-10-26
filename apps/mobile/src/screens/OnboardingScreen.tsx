import { definePage } from '@/lib/presentation';
import { t } from '../lib/i18n/index.ts';

export const OnboardingScreen = definePage({
  id: 'onboarding',
  title: t('onboarding.title'),
  native: true,
  presentation: {
    style: 'pageSheet',
    dismissible: false,
    headerShown: false,
  },
});
