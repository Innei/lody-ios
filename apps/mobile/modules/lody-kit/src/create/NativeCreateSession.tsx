import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';
import type { ChatDraftAttachment } from '../chat/NativeChat';

type Event<T> = (event: NativeSyntheticEvent<T>) => void;

export type CreateSessionRequest = {
  id: string;
  kind: 'options' | 'repositories' | 'browse';
  projectId?: string;
};

export type CreateSessionSubmit = {
  draft: string;
  payload: {
    id: string;
    text: string;
    startedAt: number;
    attachments: ChatDraftAttachment[];
  };
};

export type CreateSessionSelection = {
  workspaceId: string;
  projectId: string;
  machineId: string;
  agentConfigId: string;
  cliType: string;
  agentType: string;
};

export const NativeCreateSession: ComponentType<
  ViewProps & {
    configJSON: string;
    responseJSON?: string;
    composerRelay?: boolean;
    sendHandoff?: boolean;
    restoreDraftToken?: number;
    mentionItemsJSON?: string;
    mentionResultJSON?: string;
    onRequest: Event<CreateSessionRequest>;
    onPrefs: Event<{ json: string }>;
    onSelection?: Event<CreateSessionSelection>;
    onSubmit: Event<CreateSessionSubmit>;
    onRelayReady?: () => void;
    onMentionBrowse?: Event<{ category: string; query: string }>;
    onCancel: () => void;
  }
> = requireNativeView('LodyKit', 'LodyCreateSessionView');
