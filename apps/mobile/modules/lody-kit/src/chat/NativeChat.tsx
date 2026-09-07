import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type ChatDraftAttachment = {
  id: string;
  name: string;
  uri: string;
  kind: 'image' | 'file';
};

export const NativeChat: ComponentType<
  ViewProps & {
    entriesJSON: string;
    pendingSendJSON?: string;
    attachmentContextJSON?: string;
    navigationTitle?: string;
    navigationSubtitle?: string;
    onTitlePress?: () => void;
    processEntryId?: string;
    processStartId?: string;
    composerJSON: string;
    composerOptionsJSON?: string;
    initialDraft?: string;
    draftKey?: string;
    initialAttachmentsJSON?: string;
    clearDraftToken: number;
    restoreDraftToken?: number;
    emptyText: string;
    onSend: (
      event: NativeSyntheticEvent<{
        id: string;
        text: string;
        attachments: ChatDraftAttachment[];
      }>,
    ) => void;
    onActivityPress: (
      event: NativeSyntheticEvent<{
        entryId: string;
        itemId: string;
        processStartId?: string;
      }>,
    ) => void;
    onTurnChangesPress?: (
      event: NativeSyntheticEvent<{ entryId: string; path: string }>,
    ) => void;
    onReconnect: () => void;
    onComposerOptionChange?: (
      event: NativeSyntheticEvent<{ modelId: string; effort: string }>,
    ) => void;
  }
> = requireNativeView('LodyKit', 'LodyChatView');
