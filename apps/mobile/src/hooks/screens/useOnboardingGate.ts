import { useEffect, useRef, useState } from 'react';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { offerCommunityNotice } from '@/features/community/notice';
import { present } from '@/lib/presentation';
import { OnboardingScreen } from '@/screens/OnboardingScreen';
import { getLayoutMode } from '@/lib/presentation/layoutMode';
import { uiVerify } from '@/lib/uiVerify';

export function useOnboardingGate() {
  const { account, localReady } = useAuth();
  const presenting = useRef(false);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    if (uiVerify || !localReady || presenting.current) return;
    if (!account) {
      presenting.current = true;
      present(OnboardingScreen, undefined, {
        style: getLayoutMode() === 'compact' ? 'pageSheet' : 'formSheet',
      }).then(
        (result) => {
          presenting.current = false;
          if (result.status === 'cancelled') setAttempt((n) => n + 1);
          else void offerCommunityNotice();
        },
        () => {
          presenting.current = false;
        },
      );
      return;
    }
    void offerCommunityNotice();
  }, [account, localReady, attempt]);
}
