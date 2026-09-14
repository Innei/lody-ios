// Inlined at bundle time. TestFlight omits the flag. The fixture Simulator
// Release build sets EXPO_PUBLIC_UI_VERIFY=1 so offline scenes stay on without
// Metro or __DEV__.
export const uiVerify = process.env.EXPO_PUBLIC_UI_VERIFY === '1';

// Available only in the offline verification bundle; no production control surface.
declare global {
  var __lodyUiVerifyReset: (() => void) | undefined;
  var __lodyUiVerifyPermissionTarget:
    ((available: boolean) => void) | undefined;
  var __lodyUiVerifyQuestion:
    | {
        remoteAnswer: () => void;
        answers?: import('../models/session.ts').QuestionAnswers;
        attempts: number;
      }
    | undefined;
}
