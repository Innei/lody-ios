import { definePage } from '@/lib/presentation';

export const GitHubSettingsScreen = definePage({
  id: 'github-settings',
  title: 'GitHub',
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
