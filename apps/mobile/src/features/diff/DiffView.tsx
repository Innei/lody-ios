import type { DOMProps } from 'expo/dom';
import type { NativeSyntheticEvent } from 'react-native';
import DiffDocument, { type DiffDocumentProps } from './DiffDocument';

type DiffMessage = NativeSyntheticEvent<{ data: string }>;

export type DiffViewProps = DiffDocumentProps & {
  dom?: DOMProps & {
    shared?: boolean;
    onMessage?: (event: DiffMessage) => void;
  };
};

export function DiffView(props: DiffViewProps) {
  return <DiffDocument {...props} />;
}
