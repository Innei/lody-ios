// Expo inlines this flag into the development bundle. Release builds cannot opt in.
export const uiVerify = __DEV__ && process.env.EXPO_PUBLIC_UI_VERIFY === '1';

// Available only in the offline verification bundle; no production control surface.
declare global {
  var __lodyUiVerifyReset: (() => void) | undefined;
  var __lodyUiVerifyPermissionTarget:
    ((available: boolean) => void) | undefined;
  var __lodyUiVerifyQuestion:
    | {
        remoteAnswer: () => void;
        answers?: import('../../models/session.ts').QuestionAnswers;
        attempts: number;
      }
    | undefined;
}
