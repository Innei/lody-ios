import { saveQuickReplies } from '@lody-ios/kit';
import type { QuickReply } from '@lody/cloud-runtime/models/settings';
import { t } from '@/lib/i18n';
import { setPreferences, usePreferences } from '@/lib/preferences';
import { showToast } from '@/ui/toast';

function setQuickReplies(items: QuickReply[]) {
  if (saveQuickReplies(JSON.stringify(items))) {
    setPreferences({ quickReplies: items });
    return true;
  }
  showToast(t('settings.quickReplies.saveFailed'), 'error');
  return false;
}

export function useQuickReplies() {
  const { quickReplies } = usePreferences();
  return { quickReplies, setQuickReplies };
}
