import {
  NativeSplit,
  NativeSplitContent,
  type NativeSplitLayout,
  NativeNavigationHeader,
  panelScrollEdgeEffects,
  shellEnabled,
} from '@lody-ios/kit';
import { Stack } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { ScreenStack, ScreenStackItem } from 'react-native-screens';
import { SessionScreen, type SessionParams } from '@/screens/SessionScreen';
import { PageRuntimeProvider, type PageRuntime } from '@/lib/presentation/page';
import {
  homeScope,
  setHomeDetail,
  useHomeDetail,
} from '@/lib/presentation/homeDetail';
import type { LayoutMode } from '@/lib/presentation/layoutMode';
import { closePanel, panelPresent } from '@/lib/presentation/panelStore';
import { PanelLevels, usePanelEntries } from '@/lib/presentation/PanelStack';
import {
  SheetHeaderContext,
  type SheetHeaderItems,
} from '@/lib/presentation/SheetStack';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { PadSidebar } from './pad/PadSidebar';

const chatPresent = panelPresent('replace');

export function PadHome({ mode }: { mode: Exclude<LayoutMode, 'compact'> }) {
  const { account } = useAuth();
  const { selected } = useCatalog();
  const scope = homeScope(account?.user.id, selected?.id);
  const lastScope = useRef(scope);
  useEffect(() => {
    if (lastScope.current === scope) return;
    lastScope.current = scope;
    setHomeDetail(undefined);
    closePanel();
  }, [scope]);
  // Replace both columns together: a workspace must never inherit the old
  // conversation, project stack, search, or an in-flight creation callback.
  return <PadWorkspace key={scope} mode={mode} scope={scope} />;
}

function PadWorkspace({
  mode,
  scope,
}: {
  mode: Exclude<LayoutMode, 'compact'>;
  scope: string;
}) {
  const colors = usePalette();
  const [columns, setColumns] = useState<NativeSplitLayout>();
  const current = useHomeDetail<SessionParams>(scope);
  const detail = current?.value;
  const entries = usePanelEntries();
  const panelEntries = detail ? entries : [];
  const [detailHeaderItems, setDetailHeaderItems] =
    useState<SheetHeaderItems>();
  const closeDetail = useCallback(() => {
    setHomeDetail(undefined);
    closePanel();
  }, []);
  const runtime = useMemo<PageRuntime<SessionParams> | null>(() => {
    if (!detail) return null;
    return {
      cancel: closeDetail,
      finish: closeDetail,
      params: detail,
      present: chatPresent,
      push: chatPresent,
      source: 'route',
    };
  }, [closeDetail, detail]);

  return (
    <View
      testID="ipad-home"
      style={[styles.root, { backgroundColor: colors.reading }]}
    >
      <PadChrome />
      <NativeSplit
        style={styles.stack}
        detailRequest={current?.request ?? 0}
        layoutMode={mode}
        panelOpen={mode === 'wide' && panelEntries.length > 0}
        onColumnLayout={({ nativeEvent }) =>
          setColumns((previous) => ({ ...previous, ...nativeEvent }))
        }
      >
        <PadSidebar
          frame={columns?.primary}
          selectedSessionId={detail?.session.id}
        />
        <ScreenStack style={[StyleSheet.absoluteFill, columns?.secondary]}>
          {detail && runtime ? (
            <ScreenStackItem
              key="session-detail"
              screenId={`ipad-session-${detail.session.id}`}
              replaceAnimation="push"
              style={StyleSheet.absoluteFill}
              contentStyle={{ backgroundColor: colors.reading }}
              scrollEdgeEffects={panelScrollEdgeEffects}
              headerConfig={{
                backgroundColor: 'transparent',
                headerLeftBarButtonItems: detailHeaderItems?.left,
                headerRightBarButtonItems: detailHeaderItems?.right,
                hideShadow: true,
                title: '',
                translucent: true,
              }}
            >
              <SheetHeaderContext value={setDetailHeaderItems}>
                <PageRuntimeProvider value={runtime}>
                  <NativeSplitContent edges={{ left: true, right: true }}>
                    {/* Ancestor opacity animations suppress UIKit's composer glass. */}
                    <View key={detail.session.id} style={styles.stack}>
                      <SessionScreen.Component />
                    </View>
                  </NativeSplitContent>
                </PageRuntimeProvider>
              </SheetHeaderContext>
            </ScreenStackItem>
          ) : (
            <ScreenStackItem
              key="detail-placeholder"
              screenId="ipad-detail-placeholder-screen"
              style={StyleSheet.absoluteFill}
              contentStyle={{ backgroundColor: colors.reading }}
              headerConfig={{
                backgroundColor: 'transparent',
                hideShadow: true,
                title: '',
                translucent: true,
              }}
            >
              <NativeSplitContent edges={{ left: true, right: true }}>
                <View
                  testID="ipad-detail-placeholder"
                  style={styles.placeholder}
                >
                  <Text
                    style={[styles.placeholderTitle, { color: colors.label }]}
                  >
                    {t('ipad.detail.title')}
                  </Text>
                  <Text
                    style={[
                      styles.placeholderBody,
                      { color: colors.secondaryLabel },
                    ]}
                  >
                    {t('ipad.detail.message')}
                  </Text>
                </View>
              </NativeSplitContent>
            </ScreenStackItem>
          )}
        </ScreenStack>
        <ScreenStack style={[StyleSheet.absoluteFill, columns?.inspector]}>
          {mode === 'wide' && panelEntries.length > 0 ? (
            <PanelLevels
              entries={panelEntries}
              backgroundColor={colors.reading}
            />
          ) : (
            <ScreenStackItem
              key="inspector-empty"
              screenId="ipad-inspector-empty"
              style={StyleSheet.absoluteFill}
              headerConfig={{ hidden: true }}
            >
              <View />
            </ScreenStackItem>
          )}
        </ScreenStack>
      </NativeSplit>
    </View>
  );
}

function RouterPadChrome() {
  return <Stack.Screen options={{ headerShown: false, title: '' }} />;
}

function ShellPadChrome() {
  return <NativeNavigationHeader barHidden />;
}

const PadChrome = shellEnabled ? ShellPadChrome : RouterPadChrome;

const styles = StyleSheet.create({
  root: { flex: 1 },
  stack: { flex: 1 },
  placeholder: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 48,
  },
  placeholderTitle: { fontSize: 24, fontWeight: '600' },
  placeholderBody: {
    fontSize: 16,
    lineHeight: 22,
    marginTop: 8,
    maxWidth: 360,
    textAlign: 'center',
  },
});
