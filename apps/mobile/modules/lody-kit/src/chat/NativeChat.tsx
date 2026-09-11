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
    debugBenchmarkRun?: number;
    debugStreamBenchmarkRun?: number;
    pendingSendJSON?: string;
    attachmentContextJSON?: string;
    navigationTitle?: string;
    navigationSubtitle?: string;
    navigationMachine?: string;
    mentionRepository?: string;
    onTitlePress?: () => void;
    processEntryId?: string;
    processStartId?: string;
    composerJSON: string;
    composerOptionsJSON?: string;
    mentionItemsJSON?: string;
    mentionResultJSON?: string;
    onMentionBrowse?: (
      event: NativeSyntheticEvent<{ category: string; query: string }>,
    ) => void;
    initialDraft?: string;
    appendDraftJSON?: string;
    draftKey?: string;
    initialAttachmentsJSON?: string;
    clearDraftToken: number;
    restoreDraftToken?: number;
    emptyText: string;
    onStop?: () => void;
    onSteer?: (event: NativeSyntheticEvent<{ id: string }>) => void;
    onSend: (
      event: NativeSyntheticEvent<{
        id: string;
        text: string;
        startedAt: number;
        queue?: boolean;
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
    onFilePress?: (
      event: NativeSyntheticEvent<{ path: string; line?: number }>,
    ) => void;
    onTurnChangesPress?: (
      event: NativeSyntheticEvent<{ entryId: string; path: string }>,
    ) => void;
    onReconnect: () => void;
    onRetrySend?: () => void;
    onComposerOptionChange?: (
      event: NativeSyntheticEvent<{
        modelId: string;
        effort: string;
        fast?: boolean;
      }>,
    ) => void;
  }
> = requireNativeView('LodyKit', 'LodyChatView');
