import { useState } from 'react';
import { AuthContext } from '@/cloud/auth/AuthProvider';
import { definePage } from '@/lib/presentation';
import { OnboardingScreen } from '../OnboardingScreen';
import { t } from '../../lib/i18n/index.ts';

type Phase = 'idle' | 'waiting' | 'error' | 'signedIn';

const noop = async () => {};
const account = {
  token: '',
  user: { id: 'ui-onboarding', name: 'UI Preview', email: '' },
  workspaces: [],
};

// Connect → waiting, Cancel → error, Try again → signed in; the sheet must close on its own.
function View() {
  const [phase, setPhase] = useState<Phase>('idle');
  const next: Record<Phase, Phase> = {
    idle: 'waiting',
    waiting: 'waiting',
    error: 'signedIn',
    signedIn: 'signedIn',
  };
  return (
    <AuthContext
      value={{
        account: phase === 'signedIn' ? account : null,
        busy: phase === 'waiting',
        localReady: true,
        initialWorkspace: '',
        initialCatalog: null,
        code:
          phase === 'waiting'
            ? {
                device_code: 'ui',
                user_code: 'WXYZ-1234',
                verification_uri_complete: '',
                expires_in: 600,
                interval: 5,
              }
            : null,
        error: phase === 'error' ? t('auth.error.cancelledSignIn') : null,
        login: async () => setPhase(next[phase]),
        cancel: () => setPhase('error'),
        restore: noop,
        logout: noop,
        reopen: noop,
        updateWorkspace: noop,
        updateWorkspaceIcon: async () => '',
      }}
    >
      <OnboardingScreen.Component />
    </AuthContext>
  );
}

export const OnboardingPreviewScreen = definePage({
  id: 'onboarding-preview',
  title: t('onboarding.title'),
  Component: View,
  presentation: OnboardingScreen.presentation,
});
