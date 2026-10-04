import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { ViewProps } from 'react-native';

type Props = ViewProps & { onClose: () => void };
let Preview: ComponentType<Props>;
export function ComposerHandoffPOC(props: Props) {
  Preview ??= requireNativeView('LodyKit', 'LodyComposerHandoffPOC');
  return <Preview {...props} />;
}
