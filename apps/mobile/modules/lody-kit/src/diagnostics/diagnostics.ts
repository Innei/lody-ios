import { native } from '../runtime/LodyKit';

export type DiagnosticsRange = 900 | 3600 | 86400 | 604800;
export const diagnosticCount = (window: DiagnosticsRange) =>
  native.diagnosticCount(window);
export const shareDiagnostics = (window: DiagnosticsRange) =>
  native.shareDiagnostics(window);
export const clearDiagnostics = () => native.clearDiagnostics();
export const debugSeedDiagnostics = () => native.debugSeedDiagnostics();
export const recordPushNavigation = (
  id: string,
  source: 'notification' | 'deep-link',
  outcome: 'wait' | 'workspace' | 'discard' | 'session' | 'reset',
  reason: string = '',
) => native.recordPushNavigation(id, source, outcome, reason);
