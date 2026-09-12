import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

type ShellProps = ViewProps & {
  collectionSidebar?: boolean;
  onAction: (
    event: NativeSyntheticEvent<{
      action: string;
      text?: string;
      count?: number;
    }>,
  ) => void;
};
type PageProps = ViewProps & { pageKind: 'root' | 'project' | 'detail' };
let Shell: ComponentType<ShellProps>;
let Page: ComponentType<PageProps>;

export function NativeShellPOC(props: ShellProps) {
  Shell ??= requireNativeView('LodyKit', 'LodyNativeShellPOC');
  return <Shell {...props} />;
}

export function NativePagePOC(props: PageProps) {
  Page ??= requireNativeView('LodyKit', 'LodyNativePagePOC');
  return <Page {...props} {...{ layoutRoot: true }} />;
}
