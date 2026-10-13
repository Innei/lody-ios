import {
  diagnosticCount,
  shareDiagnostics,
  clearDiagnostics,
  type DiagnosticsRange,
} from '@lody-ios/kit';

export type DiagnosticsService = {
  count: (window: DiagnosticsRange) => Promise<number>;
  share: (window: DiagnosticsRange) => Promise<void>;
  clear: () => Promise<void>;
};

export const diagnosticsService: DiagnosticsService = {
  count: diagnosticCount,
  share: shareDiagnostics,
  clear: clearDiagnostics,
};
