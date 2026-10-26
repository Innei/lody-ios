import { definePage } from '@/lib/presentation';

export const LiveActivityPreviewScreen = definePage<Record<string, never>>({
  id: 'live-activity-preview',
  title: 'Live Activity 演示',
  native: true,
  presentation: { style: 'push' },
});
