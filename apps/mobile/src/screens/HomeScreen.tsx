import { useLayoutEffect, useRef } from 'react';
import { StyleSheet, View } from 'react-native';
import { useNavigation } from 'expo-router';
import { shellEnabled } from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import {
  getHomeDetail,
  homeScope,
  setHomeDetail,
} from '@/lib/presentation/homeDetail';
import {
  extractCompactStack,
  insertSessionRoute,
  type StackRoute,
} from '@/lib/presentation/homeTransitions';
import { type LayoutMode, useLayoutMode } from '@/lib/presentation/layoutMode';
import { openPanel } from '@/lib/presentation/panelStore';
import { getPresentationSession } from '@/lib/presentation/presentationStore';
import { t } from '@/lib/i18n';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { InboxScreen } from './InboxScreen';
import { PadHome } from './PadHomeScreen';
import { usePanelSheet } from './PanelSheetScreen';
import { SessionScreen, type SessionParams } from './SessionScreen';

function presentedRoute(route: StackRoute) {
  if (!route.params || !('presentationId' in route.params)) return undefined;
  return getPresentationSession(Number(route.params.presentationId));
}

function useHomeTransitions(mode: LayoutMode) {
  const navigation = useNavigation();
  const { account } = useAuth();
  const { selected } = useCatalog();
  const scope = homeScope(account?.user.id, selected?.id);
  const previous = useRef(mode);
  useLayoutEffect(() => {
    const from = previous.current;
    previous.current = mode;
    if (from === mode || (from !== 'compact' && mode !== 'compact')) return;
    const state = navigation.getState();
    if (!state) return;
    const routes = state.routes as StackRoute[];
    if (from === 'compact') {
      const stack = extractCompactStack(
        routes,
        presentedRoute,
        SessionScreen.id,
      );
      if (stack.session !== undefined) setHomeDetail(stack.session, scope);
      stack.panel.forEach(
        (entry, index) =>
          void openPanel(
            entry.page,
            entry.params,
            index === 0 ? 'replace' : 'push',
            entry.presentation,
          ),
      );
      if (stack.routes === routes) return;
      navigation.dispatch({
        type: 'RESET',
        payload: {
          ...state,
          routes: stack.routes,
          index: stack.routes.length - 1,
        },
      });
      return;
    }
    const detail = getHomeDetail<SessionParams>(scope);
    if (!detail) return;
    let presentationId: number | undefined;
    void present(SessionScreen, detail.value, {
      title: detail.value.session.title,
      animationType: 'none',
      host: (session) => {
        presentationId = session.id;
      },
    });
    setHomeDetail(undefined);
    if (presentationId === undefined) return;
    const next = insertSessionRoute(routes, presentationId);
    navigation.dispatch({
      type: 'RESET',
      payload: { ...state, routes: next, index: next.length - 1 },
    });
  }, [mode, navigation, scope]);
}

// The shell is compact-only for now; its pages are not Router routes to move.
const useTransitions = shellEnabled ? () => {} : useHomeTransitions;

function Home() {
  const mode = useLayoutMode();
  useTransitions(mode);
  usePanelSheet(mode);
  return (
    <View testID="home" style={styles.root}>
      {mode === 'compact' ? <InboxScreen.Component /> : <PadHome mode={mode} />}
    </View>
  );
}

const styles = StyleSheet.create({ root: { flex: 1 } });

export const HomeScreen = definePage({
  id: 'home',
  title: t('tabs.sessions'),
  Component: Home,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
