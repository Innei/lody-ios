import { useMemo, useState } from 'react';
import { ActivityIndicator, Text, View as RNView } from 'react-native';
import type { HeaderBarButtonItemMenuAction } from 'react-native-screens';
import { NativeNavigationHeader, SimulatorView } from '@lody-ios/kit';
import {
  simulatorPhaseKey,
  simulatorSource,
  startSimulator,
  stopSimulator,
  useSimulatorOperation,
} from '@/features/simulator/operations';
import { definePage } from '@/lib/presentation';
import type { HeaderItems } from '@/lib/presentation/SheetStack';
import { usePalette } from '@/lib/theme/palette';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { t, type TranslationKey } from '../lib/i18n/index.ts';

export type SimulatorParams = { sessionId: string };

type Action = { id: string; key: TranslationKey; symbol: string };

const SECTIONS: Action[][] = [
  [
    {
      id: 'app-switcher',
      key: 'simulator.action.appSwitcher',
      symbol: 'square.stack',
    },
    { id: 'lock', key: 'simulator.action.lock', symbol: 'lock' },
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
];

function View() {
  const { params, cancel, present } = usePageRuntime<SimulatorParams>();
  const colors = usePalette();
  const operation = useSimulatorOperation(params.sessionId);
  const [command, setCommand] = useState({ token: 0, action: '' });
  const source = simulatorSource(operation);
  const sourceJSON = source ? JSON.stringify(source) : '';
  const live = Boolean(source);
  const headerItems = useMemo<HeaderItems>(() => {
    const run = (action: string) =>
      setCommand((previous) => ({ token: previous.token + 1, action }));
    const item = (action: Action): HeaderBarButtonItemMenuAction => ({
      type: 'action',
      title: t(action.key),
      icon: { type: 'sfSymbol', name: action.symbol },
      disabled: !live,
      onPress: () => run(action.id),
    });
    const workspaceId = operation?.workspaceId;
    const chooseAnother: HeaderBarButtonItemMenuAction = {
      type: 'action',
      title: t('simulator.chooseAnother'),
      icon: { type: 'sfSymbol', name: 'iphone.gen3' },
      disabled: !workspaceId,
      onPress: () => {
        if (!workspaceId) return;
        void import('./SimulatorPickerScreen').then(
          async ({ SimulatorPickerScreen }) => {
            const result = await present(SimulatorPickerScreen, {
              workspaceId,
              sessionId: params.sessionId,
            });
            if (result.status === 'completed')
              void startSimulator(workspaceId, params.sessionId, result.value);
          },
        );
      },
    };
    const stop: HeaderBarButtonItemMenuAction = {
      type: 'action',
      title: t('simulator.stop'),
      icon: { type: 'sfSymbol', name: 'stop.circle' },
      destructive: true,
      onPress: () => {
        void stopSimulator(params.sessionId);
        cancel();
      },
    };
    return [
      {
        type: 'button',
        icon: { type: 'sfSymbol', name: 'house' },
        accessibilityLabel: t('simulator.action.home'),
        disabled: !live,
        onPress: () => run('home'),
      },
      {
        type: 'menu',
        icon: { type: 'sfSymbol', name: 'ellipsis' },
        accessibilityLabel: t('common.more'),
        menu: {
          items: [
            ...SECTIONS.map((section) => ({
              type: 'submenu' as const,
              displayInline: true,
              items: section.map(item),
            })),
            {
              type: 'submenu',
              displayInline: true,
              items: [chooseAnother, stop],
            },
          ],
        },
      },
    ];
  }, [cancel, live, operation?.workspaceId, params.sessionId, present]);

  return (
    <RNView style={{ flex: 1, backgroundColor: colors.background }}>
      <NativeNavigationHeader items={headerItems} title={operation?.name} />
      {source ? (
        <SimulatorView
          style={{ flex: 1 }}
          sourceJSON={sourceJSON}
          commandJSON={JSON.stringify(command)}
        />
      ) : (
        <RNView
          style={{
            flex: 1,
            alignItems: 'center',
            justifyContent: 'center',
            gap: 12,
            padding: 32,
          }}
        >
          {operation?.phase !== 'failed' && operation?.phase !== 'closed' && (
            <ActivityIndicator />
          )}
          <Text
            style={{ color: colors.secondaryLabel, textAlign: 'center' }}
            accessibilityRole="text"
          >
            {t(simulatorPhaseKey[operation?.phase ?? 'closed'])}
          </Text>
          {operation?.message && operation.phase === 'failed' && (
            <Text style={{ color: colors.tertiaryLabel, textAlign: 'center' }}>
              {operation.message}
            </Text>
          )}
        </RNView>
      )}
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
