import { useEffect } from 'react';
import { Dimensions, StyleSheet } from 'react-native';
import { ThemeProvider } from 'expo-router';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { NativeLayoutProbe } from '@lody-ios/kit';
import { PushCoordinator } from '@/features/notifications/PushCoordinator';
import { ShareCoordinator } from '@/features/share/ShareCoordinator';
import { ShareSnapshot } from '@/features/share/ShareSnapshot';
import { useBindSessionNav } from '@/hooks/screens/useBindSessionNav';
import { useOnboardingGate } from '@/hooks/screens/useOnboardingGate';
import { assertVendoredDomWebView } from '@/lib/assert-vendored-dom-webview';
import { present } from '@/lib/presentation';
import {
  guessLayoutTraits,
  setLayoutTraits,
} from '@/lib/presentation/layoutMode';
import { useNavigationTheme } from '@/lib/theme/navigationTheme';
import { uiVerify } from '@/lib/uiVerify';
import { DebugScreen } from '@/screens/debug/DebugScreen';
import { homeVerify } from '@/screens/debug/HomePreviewScreen';
import { VerifyProviders } from '@/screens/debug/verifyProviders';
import { HomeScreen } from '@/screens/HomeScreen';
import { useShellLinks } from './shellLinks';
import { PublishSafeArea } from './shellSafeArea';

const initialWindow = Dimensions.get('window');
setLayoutTraits(guessLayoutTraits(initialWindow.width, initialWindow.height));

const debugIsRoot = uiVerify && !homeVerify;
let started = false;

function Bindings() {
  useBindSessionNav();
  useOnboardingGate();
  useShellLinks(debugIsRoot);
  useEffect(() => {
    if (__DEV__) assertVendoredDomWebView();
    if (started) return;
    started = true;
    if (debugIsRoot) void present(DebugScreen, undefined, { root: true });
    // Router's index route shows no title over Home's own header items.
    else void present(HomeScreen, undefined, { root: true, title: '' });
  }, []);
  return null;
}

export function ShellRoot() {
  const theme = useNavigationTheme();
  return (
    <SafeAreaProvider>
      <ThemeProvider value={theme}>
        <VerifyProviders>
          <NativeLayoutProbe
            pointerEvents="none"
            style={StyleSheet.absoluteFill}
            onTraits={({ nativeEvent }) => setLayoutTraits(nativeEvent)}
          />
          <PublishSafeArea />
          <Bindings />
          <PushCoordinator />
          <ShareSnapshot />
          <ShareCoordinator />
        </VerifyProviders>
      </ThemeProvider>
    </SafeAreaProvider>
  );
}
