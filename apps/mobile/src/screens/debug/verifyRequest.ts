import { useSyncExternalStore } from 'react';
import { useLocalSearchParams } from 'expo-router';
import { shellEnabled } from '@lody-ios/kit';

export type VerifyRequest = { verifyCase?: string; request?: string };

let current: VerifyRequest = {};
const listeners = new Set<() => void>();

export function setVerifyRequest(next: VerifyRequest) {
  current = next;
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function useShellVerifyRequest() {
  return useSyncExternalStore(subscribe, () => current);
}

function useRouterVerifyRequest() {
  return useLocalSearchParams<VerifyRequest>();
}

export const useVerifyRequest = shellEnabled
  ? useShellVerifyRequest
  : useRouterVerifyRequest;
