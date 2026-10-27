import { definePage } from '@/lib/presentation';
export const PullRequestNativePreviewScreen = definePage<{
  mode: string;
  state: string;
  onInvestigate: (text: string) => void;
}>({
  id: 'pull-request-native-preview',
  title: 'PR',
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
