import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export const NativeCreateSession: ComponentType<
  ViewProps & {
    snapshotJSON: string;
    busy: boolean;
    openCreated: boolean;
    onOpenCreated: () => void;
    onCancel: () => void;
    composerRelay: boolean;
    restoreDraftToken: number;
    mentionItemsJSON: string;
    mentionResultJSON: string;
    onMentionBrowse: (
      event: NativeSyntheticEvent<{ category: string; query: string }>,
    ) => void;
    onSubmit: (event: NativeSyntheticEvent<{ json: string }>) => void;
    onPreferences: (event: NativeSyntheticEvent<{ json: string }>) => void;
    onSelection: (
      event: NativeSyntheticEvent<{ projectId: string; source: string }>,
    ) => void;
    onRelayReady: () => void;
  }
> = requireNativeView('LodyKit', 'LodyCreateSessionView');
