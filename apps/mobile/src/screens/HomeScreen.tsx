import { useLayoutEffect, useRef } from 'react';
import { StyleSheet, View } from 'react-native';
import { NativeInbox } from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import {
  getHomeDetail,
  homeScope,
  setHomeDetail,
} from '@/lib/presentation/homeDetail';
import {
  extractCompactStack,
  type StackRoute,
} from '@/lib/presentation/homeTransitions';
import { type LayoutMode, useLayoutMode } from '@/lib/presentation/layoutMode';
import { openPanel } from '@/lib/presentation/panelStore';
import { getPresentationSession } from '@/lib/presentation/presentationStore';
import {
  shellSetStack,
  shellStackRoutes,
} from '@/lib/presentation/shellNavigation';
import { t } from '@/lib/i18n';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { PadHome } from './PadHomeScreen';
import { usePanelSheet } from './PanelSheetScreen';
import { SessionScreen, type SessionParams } from './SessionScreen';

function presentedRoute(route: StackRoute) {
  if (!route.params || !('presentationId' in route.params)) return undefined;
  return getPresentationSession(Number(route.params.presentationId));
}

function useHomeTransitions(mode: LayoutMode) {
  const { account } = useAuth();
  const { selected } = useCatalog();
  const scope = homeScope(account?.user.id, selected?.id);
  const previous = useRef(mode);
  useLayoutEffect(() => {
    const from = previous.current;
    previous.current = mode;
    if (from === mode || (from !== 'compact' && mode !== 'compact')) return;
    if (from === 'compact') {
      const routes = shellStackRoutes();
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
      if (stack.routes !== routes) void shellSetStack(stack.routes);
      return;
    }
    const detail = getHomeDetail<SessionParams>(scope);
    if (!detail) return;
    void present(SessionScreen, detail.value, {
      title: detail.value.session.title,
      animationType: 'none',
      insertAt: 1,
    });
    setHomeDetail(undefined);
  }, [mode, scope]);
}

function Home() {
  const mode = useLayoutMode();
  useHomeTransitions(mode);
  usePanelSheet(mode);
  return (
    <View testID="home" style={styles.root}>
      {mode === 'compact' ? (
        <NativeInbox style={styles.root} />
      ) : (
        <PadHome mode={mode} />
      )}
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
