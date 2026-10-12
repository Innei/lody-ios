import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type HTMLPreviewIssue = {
  reference: string;
  path?: string;
  kind: string;
  code: string;
};

export type NativeHTMLPreviewViewProps = ViewProps & {
  handle: string;
  responsesJSON: string;
  onResourceRequest: (
    event: NativeSyntheticEvent<{ id: string; path: string }>,
  ) => void;
  onIssues: (
    event: NativeSyntheticEvent<{ issues: HTMLPreviewIssue[] }>,
  ) => void;
  onLoad: () => void;
  onFail: (event: NativeSyntheticEvent<{ code: string }>) => void;
};

export const NativeHTMLPreviewView: ComponentType<NativeHTMLPreviewViewProps> =
  requireNativeView('LodyKit', 'LodyHTMLPreviewView');
