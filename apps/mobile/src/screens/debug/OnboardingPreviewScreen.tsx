import { definePage } from '@/lib/presentation';
import { OnboardingScreen } from '../OnboardingScreen';
import { t } from '../../lib/i18n/index.ts';

export const OnboardingPreviewScreen = definePage({
  id: 'onboarding-preview',
  title: t('onboarding.title'),
  native: true,
  presentation: OnboardingScreen.presentation,
});
