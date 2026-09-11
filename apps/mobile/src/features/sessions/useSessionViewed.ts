import { useCallback } from 'react';
import { useFocusEffect } from 'expo-router';
import { AppState } from 'react-native';
import { showToast } from '../../ui/toast.ts';
import { t } from '../../lib/i18n/index.ts';
import { getSessionViewStore } from './sessionViewStore.ts';

export function useSessionViewed(
  userId: string,
  workspaceId: string,
  sessionId: string,
  lastMessageAt?: number,
) {
  useFocusEffect(
    useCallback(() => {
      const mark = () => {
        if (AppState.currentState !== 'active') return;
        void getSessionViewStore(userId, workspaceId)
          .markViewed(sessionId, lastMessageAt)
          .catch(() => showToast(t('catalog.toast.localSaveFailed')));
      };
      mark();
      const subscription = AppState.addEventListener('change', mark);
      return () => subscription.remove();
    }, [userId, workspaceId, sessionId, lastMessageAt]),
  );
}
