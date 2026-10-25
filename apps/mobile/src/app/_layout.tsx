import { useEffect } from 'react';
import { PushCoordinator } from '@/features/notifications/PushCoordinator';
import { ShareSnapshot } from '@/features/share/ShareSnapshot';
import { ShareCoordinator } from '@/features/share/ShareCoordinator';
import { Stack, ThemeProvider } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Dimensions, StyleSheet } from 'react-native';
import { nativePresentationOptions } from '@/lib/presentation';
import { useNavigationTheme } from '@/lib/theme/navigationTheme';
import { NativeLayoutProbe, navigationScrollEdgeEffects } from '@lody-ios/kit';
import { useBindSessionNav } from '@/hooks/screens/useBindSessionNav';
import { useOnboardingGate } from '@/hooks/screens/useOnboardingGate';
import { assertVendoredDomWebView } from '@/lib/assert-vendored-dom-webview';
import { VerifyProviders } from '@/screens/debug/verifyProviders';
import {
  guessLayoutTraits,
  setLayoutTraits,
} from '@/lib/presentation/layoutMode';

export const unstable_settings = { initialRouteName: 'index' };

const initialWindow = Dimensions.get('window');
setLayoutTraits(guessLayoutTraits(initialWindow.width, initialWindow.height));

export default function RootLayout() {
  const theme = useNavigationTheme();
  return (
    <ThemeProvider value={theme}>
      <VerifyProviders>
        <NativeLayoutProbe
          pointerEvents="none"
          style={StyleSheet.absoluteFill}
          onTraits={({ nativeEvent }) => setLayoutTraits(nativeEvent)}
        />
        <Bindings />
        <PushCoordinator />
        <ShareSnapshot />
        <ShareCoordinator />
        <StatusBar style="auto" />
        <Stack
          screenOptions={{
            headerTransparent: true,
            headerLargeTitle: false,
            headerBackButtonDisplayMode: 'minimal',
            headerShadowVisible: false,
            scrollEdgeEffects: navigationScrollEdgeEffects,
          }}
        >
          <Stack.Screen name="index" options={{ title: '' }} />
          <Stack.Screen name="debug" options={{ title: 'Debug' }} />
          <Stack.Screen name="environment" options={{ title: 'Runtime' }} />
          <Stack.Screen
            name="presented/[presentationId]"
            options={({ route }) =>
              nativePresentationOptions(route.params, theme.colors.background)
            }
          />
        </Stack>
      </VerifyProviders>
    </ThemeProvider>
  );
}

function Bindings() {
  useBindSessionNav();
  useOnboardingGate();
  useEffect(() => {
    if (__DEV__) assertVendoredDomWebView();
  }, []);
  return null;
}
