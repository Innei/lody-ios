import {
  prepareSessionEdit,
  readSessionEdit,
  sendSessionEdit,
  type ChatDraftAttachment,
} from '@lody-ios/kit';

export type EditDraft = {
  state: string;
  id?: string;
  text?: string;
  attachments?: ChatDraftAttachment[];
  reason?: string;
};
export const sessionEditSource = {
  read: async (payload: string): Promise<EditDraft> =>
    JSON.parse(await readSessionEdit(payload)),
  prepare: async (payload: string): Promise<EditDraft> =>
    JSON.parse(await prepareSessionEdit(payload)),
  send: async (payload: string): Promise<EditDraft> =>
    JSON.parse(await sendSessionEdit(payload)),
};
export type SessionEditSource = typeof sessionEditSource;
