import { Linking } from 'react-native';
import {
  copyText,
  dataRuntimeStatus,
  feedbackEnvironment,
  feedbackScreenshot,
  readLocalValue,
  shareFeedback,
  writeLocalValue,
  type FeedbackEnvironment,
  type PickedWorkspaceIcon,
} from '@lody-ios/kit';
import { getConnection } from '@/cloud/catalog/connection';
import {
  createFeedbackDraftStore,
  feedbackDiagnostics,
  type FeedbackDraft,
} from './report';

export type FeedbackService = {
  load: () => Promise<FeedbackDraft>;
  save: (draft: FeedbackDraft) => Promise<void>;
  environment: () => Promise<FeedbackEnvironment>;
  diagnostics: () => Promise<string>;
  pickScreenshot: () => Promise<PickedWorkspaceIcon | null>;
  previewScreenshot: (uri: string) => Promise<PickedWorkspaceIcon | null>;
  removeScreenshot: (uri: string) => Promise<unknown>;
  copy: (report: string) => void;
  share: (report: string, uris: string[]) => Promise<boolean>;
  openGithub: (url: string) => Promise<unknown>;
};

const draftStore = createFeedbackDraftStore(
  () => readLocalValue('bug-feedback-draft'),
  (json) => writeLocalValue('bug-feedback-draft', json),
);

export const feedbackService: FeedbackService = {
  ...draftStore,
  environment: feedbackEnvironment,
  diagnostics: async () =>
    feedbackDiagnostics({
      connection: getConnection(),
      runtime: await dataRuntimeStatus(),
    }),
  pickScreenshot: () => feedbackScreenshot('pick', ''),
  previewScreenshot: (uri) => feedbackScreenshot('preview', uri),
  removeScreenshot: (uri) => feedbackScreenshot('remove', uri),
  copy: copyText,
  share: shareFeedback,
  openGithub: Linking.openURL,
};
