import { useCallback, useSyncExternalStore } from 'react';
import { useNavigationContainerRef } from 'expo-router';
import { shellEnabled } from '@lody-ios/kit';

import { useShellNavigationState } from './shellNavigation';

function useRouterNavigationState() {
  const navigation = useNavigationContainerRef();
  const subscribe = useCallback(
    (notify: () => void) => navigation.addListener('state', notify),
    [navigation],
  );
  const snapshot = useCallback(
    // Expo Router wraps the app's native Stack in its own root navigator.
    () =>
      navigation.current?.getRootState()?.routes.find((route) => route.state)
        ?.state,
    [navigation],
  );
  return useSyncExternalStore(subscribe, snapshot);
}

export const useAppNavigationState: () =>
  | { key?: string; routes: readonly { key?: string; name: string }[] }
  | undefined = shellEnabled
  ? useShellNavigationState
  : useRouterNavigationState;
