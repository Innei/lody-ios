import { useMemo, useState } from 'react';
import { View as RNView } from 'react-native';
import type { HeaderBarButtonItemMenuAction } from 'react-native-screens';
import {
  NativeNavigationHeader,
  SimulatorView,
  type SimulatorSource,
  openPreviewBrowser,
} from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import type { HeaderItems } from '@/lib/presentation/SheetStack';
import { usePalette } from '@/lib/theme/palette';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { t, type TranslationKey } from '../lib/i18n/index.ts';

export type SimulatorParams = SimulatorSource;

type Action = { id: string; key: TranslationKey; symbol: string };

const SECTIONS: Action[][] = [
  [
    {
      id: 'app-switcher',
      key: 'simulator.action.appSwitcher',
      symbol: 'square.stack',
    },
    { id: 'power', key: 'simulator.action.lock', symbol: 'lock' },
  ],
  [
    {
      id: 'rotate-left',
      key: 'simulator.action.rotateLeft',
      symbol: 'rotate.left',
    },
    {
      id: 'rotate-right',
      key: 'simulator.action.rotateRight',
      symbol: 'rotate.right',
    },
    {
      id: 'shake',
      key: 'simulator.action.shake',
      symbol: 'iphone.radiowaves.left.and.right',
    },
  ],
  [
    {
      id: 'volume-up',
      key: 'simulator.action.volumeUp',
      symbol: 'speaker.plus',
    },
    {
      id: 'volume-down',
      key: 'simulator.action.volumeDown',
      symbol: 'speaker.minus',
    },
    {
      id: 'action',
      key: 'simulator.action.actionButton',
      symbol: 'button.programmable',
    },
  ],
  [
    { id: 'screenshot', key: 'simulator.action.screenshot', symbol: 'camera' },
    { id: 'browser', key: 'simulator.action.openInBrowser', symbol: 'safari' },
  ],
];

function View() {
  const { params } = usePageRuntime<SimulatorParams>();
  const colors = usePalette();
  const [command, setCommand] = useState({ token: 0, action: '' });
  const source = useMemo(() => JSON.stringify(params), [params]);
  const headerItems = useMemo<HeaderItems>(() => {
    const run = (action: string) => {
      if (action === 'browser') {
        void openPreviewBrowser(params.url);
        return;
      }
      setCommand((previous) => ({ token: previous.token + 1, action }));
    };
    const item = (action: Action): HeaderBarButtonItemMenuAction => ({
      type: 'action',
      title: t(action.key),
      icon: { type: 'sfSymbol', name: action.symbol },
      onPress: () => run(action.id),
    });
    return [
      {
        type: 'button',
        icon: { type: 'sfSymbol', name: 'house' },
        accessibilityLabel: t('simulator.action.home'),
        onPress: () => run('home'),
      },
      {
        type: 'menu',
        icon: { type: 'sfSymbol', name: 'ellipsis' },
        accessibilityLabel: t('common.more'),
        menu: {
          items: SECTIONS.map((section) => ({
            type: 'submenu',
            displayInline: true,
            items: section.map(item),
          })),
        },
      },
    ];
  }, [params.url]);

  return (
    <RNView style={{ flex: 1, backgroundColor: colors.background }}>
      <NativeNavigationHeader items={headerItems} />
      <SimulatorView
        style={{ flex: 1 }}
        sourceJSON={source}
        commandJSON={JSON.stringify(command)}
      />
    </RNView>
  );
}

export const SimulatorScreen = definePage<SimulatorParams>({
  id: 'simulator',
  title: t('simulator.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from a session preview');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
