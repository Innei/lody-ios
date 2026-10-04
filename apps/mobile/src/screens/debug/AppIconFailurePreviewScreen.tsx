import { AppIconView } from '../AppIconScreen';
import { definePage } from '@/lib/presentation';

const service = {
  get: async () => 'default',
  set: async (): Promise<string> => {
    throw new Error('Offline icon failure fixture');
  },
};

export const AppIconFailurePreviewScreen = definePage({
  id: 'app-icon-failure-preview',
  title: 'App Icon',
  Component: () => <AppIconView service={service} />,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
