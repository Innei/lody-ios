import { definePage } from '@/lib/presentation';

export const SessionPreviewScreen = definePage<{ scenario: string }>({
  id: 'session-preview',
  title: 'Native session',
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});

export const PermissionNativePreviewScreen = definePage<{ waiting?: boolean }>({
  id: 'permission-native-preview',
  title: 'Native permission',
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
