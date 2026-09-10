import { useCallback, useSyncExternalStore } from 'react';
import { useNavigationContainerRef } from 'expo-router';

export function useAppNavigationState() {
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
