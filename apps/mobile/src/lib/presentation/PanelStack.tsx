import { useCallback, useMemo, useState, useSyncExternalStore } from 'react';
import { type ColorValue, StyleSheet } from 'react-native';
import type { SearchBarProps } from 'react-native-screens';
import {
  ScreenStack,
  ScreenStackHeaderSearchBarView,
  ScreenStackItem,
  SearchBar,
} from 'react-native-screens';
import { panelScrollEdgeEffects } from '@lody-ios/kit';

import { type PageFinish, type PageRuntime, PageRuntimeProvider } from './page';
import {
  closePanel,
  getPanelEntries,
  panelPresent,
  type PanelEntry,
  popPanel,
  subscribePanel,
} from './panelStore';
import {
  type HeaderItems,
  SheetHeaderContext,
  type SheetHeaderItems,
  SheetSearchContext,
} from './headerContext';
import { t } from '../i18n/index.ts';

export function usePanelEntries(): readonly PanelEntry[] {
  return useSyncExternalStore(subscribePanel, getPanelEntries);
}

const panelPush = panelPresent('push');

export function PanelLevels({
  entries,
  backgroundColor,
}: {
  entries: readonly PanelEntry[];
  backgroundColor: ColorValue;
}) {
  return entries.map((entry, index) => (
    <PanelLevel
      key={entry.key}
      entry={entry}
      root={index === 0}
      backgroundColor={backgroundColor}
    />
  ));
}

export function PanelStack(props: {
  entries: readonly PanelEntry[];
  backgroundColor: ColorValue;
}) {
  return (
    <ScreenStack style={StyleSheet.absoluteFill}>
      <PanelLevels {...props} />
    </ScreenStack>
  );
}

function PanelLevel({
  entry,
  root,
  backgroundColor,
}: {
  entry: PanelEntry;
  root: boolean;
  backgroundColor: ColorValue;
}) {
  const [headerItems, setHeaderItems] = useState<SheetHeaderItems>();
  const [search, setSearch] = useState<SearchBarProps>();
  const cancel = useCallback(
    () => popPanel(entry.key, { status: 'cancelled' }),
    [entry.key],
  );
  const finish = useCallback(
    (value?: unknown) => popPanel(entry.key, { status: 'completed', value }),
    [entry.key],
  ) as PageFinish<unknown>;
  const runtime = useMemo<PageRuntime<unknown, unknown>>(
    () => ({
      cancel,
      finish,
      params: entry.params,
      present: panelPush,
      push: panelPush,
      source: 'presentation',
    }),
    [cancel, finish, entry.params],
  );
  const left: HeaderItems =
    headerItems?.left ??
    (root
      ? [
          {
            type: 'button',
            accessibilityLabel: t('accessibility.closePanel'),
            icon: { type: 'sfSymbol', name: 'xmark' },
            onPress: closePanel,
          },
        ]
      : undefined);

  return (
    <ScreenStackItem
      screenId={`panel-level-${entry.key}`}
      stackPresentation={root ? undefined : 'push'}
      replaceAnimation="push"
      style={StyleSheet.absoluteFill}
      contentStyle={{ backgroundColor }}
      scrollEdgeEffects={panelScrollEdgeEffects}
      headerConfig={{
        title:
          headerItems?.title ?? entry.presentation.title ?? entry.page.title,
        hidden: !entry.presentation.headerShown,
        backButtonDisplayMode: 'minimal',
        translucent: true,
        hideShadow: true,
        backgroundColor: 'transparent',
        blurEffect:
          entry.presentation.headerVariant === 'glass'
            ? 'systemChromeMaterial'
            : 'none',
        headerLeftBarButtonItems: left,
        headerRightBarButtonItems: headerItems?.right,
        children: search ? (
          <ScreenStackHeaderSearchBarView>
            <SearchBar {...search} />
          </ScreenStackHeaderSearchBarView>
        ) : undefined,
      }}
      gestureEnabled={entry.presentation.dismissible}
      onDismissed={root ? undefined : cancel}
    >
      <SheetHeaderContext value={setHeaderItems}>
        <PageRuntimeProvider value={runtime}>
          <SheetSearchContext value={setSearch}>
            <entry.page.Component />
          </SheetSearchContext>
        </PageRuntimeProvider>
      </SheetHeaderContext>
    </ScreenStackItem>
  );
}
