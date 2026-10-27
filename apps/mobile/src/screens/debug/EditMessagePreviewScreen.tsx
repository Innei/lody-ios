import { definePage } from '@/lib/presentation';

export const EditMessagePreviewScreen = definePage<{ scenario?: string }>({
  id: 'edit-message-preview',
  title: 'Message editing',
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
