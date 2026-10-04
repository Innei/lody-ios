import { Alert, Linking } from 'react-native';
import { readLocal, writeLocal } from '@/cloud/kv';
import { t } from '../../lib/i18n/index.ts';
import { showToast } from '@/ui/toast';
import { uiVerify } from '@/lib/uiVerify';

export const COMMUNITY_REPO_URL = 'https://github.com/Innei/lody-ios';
const SEEN_KEY = 'communityNoticeSeen';
let offering = false;

export function showCommunityNotice() {
  Alert.alert(t('communityNotice.title'), t('communityNotice.message'), [
    { text: t('communityNotice.later'), style: 'cancel' },
    {
      text: t('communityNotice.star'),
      onPress: () => {
        void Linking.openURL(COMMUNITY_REPO_URL).catch(() =>
          showToast(t('settings.toast.openProjectLinkFailed')),
        );
      },
    },
  ]);
}

export async function offerCommunityNotice() {
  if (uiVerify || offering) return;
  if (await readLocal<boolean>(SEEN_KEY)) return;
  offering = true;
  await writeLocal(SEEN_KEY, true);
  showCommunityNotice();
}
