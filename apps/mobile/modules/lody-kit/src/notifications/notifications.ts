import { native } from '../runtime/LodyKit';
export type PushStatus = {
  configured: boolean;
  registered: boolean;
  permission: 'notDetermined' | 'denied' | 'authorized';
};
export type PushClick = { id: string; route: string; userId: string };
export const setPushUser = (id: string | null) => native.setPushUser(id);
export const pushStatus = () => native.pushStatus();
export const requestPushPermission = () => native.requestPushPermission();
export const pendingPushClick = () => native.pendingPushClick();
export const acknowledgePushClick = (id: string) =>
  native.acknowledgePushClick(id);
export const setPushVisibleRoute = (route: string) =>
  native.setPushVisibleRoute(route);
export const addPushClickListener = (listener: () => void) =>
  native.addListener('onPushClick', listener);

export const verifyPushSubscription = () => native.verifyPushSubscription();
