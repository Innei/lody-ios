import { native } from '../runtime/LodyKit';

export const recordPushNavigation = (
  id: string,
  source: 'notification' | 'deep-link',
  outcome: 'wait' | 'workspace' | 'discard' | 'session' | 'reset',
  reason: string = '',
) => native.recordPushNavigation(id, source, outcome, reason);
