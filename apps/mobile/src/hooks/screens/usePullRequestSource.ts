import { useCallback, useSyncExternalStore } from 'react';
import { AppState } from 'react-native';
import { useFocusEffect } from 'expo-router';
import type { PullRequestSource } from '@/features/pull-request/source';

export function usePullRequestSource(source: PullRequestSource) {
  const state = useSyncExternalStore(source.subscribe, source.getSnapshot);
  useFocusEffect(
    useCallback(() => {
      const refresh = () => {
        if (
          /unauthorized|authorization_required|forbidden/.test(
            source.getSnapshot().error ?? '',
          )
        )
          return;
        if (AppState.currentState === 'active') void source.refresh();
      };
      refresh();
      const timer = setInterval(refresh, 30_000);
      const subscription = AppState.addEventListener('change', (state) => {
        if (state === 'active') refresh();
      });
      return () => {
        clearInterval(timer);
        subscription.remove();
      };
    }, [source]),
  );
  return state;
}
