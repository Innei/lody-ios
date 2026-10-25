import { usePreferences } from '@/lib/preferences';

export function useQuickReplies() {
  const { quickReplies } = usePreferences();
  return { quickReplies };
}
