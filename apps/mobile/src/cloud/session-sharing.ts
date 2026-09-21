import { sessionSharingRaw, addDataRuntimeListener } from '@lody-ios/kit';
import type {
  ShareRequest,
  ShareState,
  ShareProgress,
} from '../models/session-sharing.ts';

export type ShareSource = {
  request: (request: ShareRequest) => Promise<ShareState | null>;
  subscribe: (listener: (progress: ShareProgress) => void) => () => void;
};
export const sessionShareSource: ShareSource = {
  request: async (request) =>
    JSON.parse(await sessionSharingRaw(JSON.stringify(request))),
  subscribe: (listener) => {
    const subscription = addDataRuntimeListener((event) => {
      if (event.shareProgress) listener(event.shareProgress);
    });
    return () => subscription.remove();
  },
};
