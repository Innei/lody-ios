import { t } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';

export const PromptShortcutsScreen = definePage({
  id: 'prompt-shortcuts',
  title: t('settings.shortcuts.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
