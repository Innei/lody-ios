import { Share } from 'react-native';
import { showToast } from '../ui/toast.ts';
import { t } from './i18n/index.ts';

// UIKit reports the pasteboard activity separately from app activities.
const COPY_ACTIVITY = 'com.apple.UIKit.activity.CopyToPasteboard';

/**
 * Presents the system share sheet for one link and reports the outcome as a
 * toast. Dismissing the sheet is a cancel, not a result worth announcing.
 */
export async function shareLink(url: string) {
  try {
    const { action, activityType } = await Share.share({ url });
    if (action === Share.dismissedAction) return;
    showToast(
      t(
        activityType === COPY_ACTIVITY
          ? 'share.toast.linkCopied'
          : 'share.toast.shared',
      ),
      'info',
    );
  } catch {
    showToast(t('share.toast.failed'));
  }
}
