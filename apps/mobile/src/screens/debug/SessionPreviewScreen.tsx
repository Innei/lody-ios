import { definePage } from '@/lib/presentation';

export const SessionPreviewScreen = definePage<{ scenario: string }>({
  id: 'session-preview',
  title: 'Native session',
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
