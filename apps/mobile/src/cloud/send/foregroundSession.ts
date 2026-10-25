import { setForegroundSession as publishForegroundSession } from '@lody-ios/kit';

let id = '';

export function setForegroundSession(next: string) {
  if (id === next) return;
  id = next;
  void publishForegroundSession(next);
}

export function getForegroundSession() {
  return id;
}
