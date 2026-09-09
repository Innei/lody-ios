import {
  homeVerify,
  HomePreviewProviders,
} from '@/screens/debug/HomePreviewScreen';
import { type PropsWithChildren, useEffect } from 'react';
import { PushCoordinator } from '@/features/notifications/PushCoordinator';
import { Stack, ThemeProvider } from 'expo-router';
import { CatalogProvider } from '@/cloud/catalog/CatalogProvider';
import { AuthProvider } from '@/cloud/auth/AuthProvider';
import { StatusBar } from 'expo-status-bar';
import { useColorScheme } from 'react-native';
import { nativePresentationOptions } from '@/lib/presentation';
import { navigationThemes } from '@/lib/theme/palette';
import { softScrollEdgeEffects } from '@/ui/Screen';
import { DiffWebViewWarmer } from '@/features/diff/DiffWebViewWarmer';
import { useBindSessionNav } from '@/hooks/screens/useBindSessionNav';
import { useOnboardingGate } from '@/hooks/screens/useOnboardingGate';
import { assertVendoredDomWebView } from '@/lib/assert-vendored-dom-webview';

export const unstable_settings = { initialRouteName: 'index' };

export default function RootLayout() {
  const theme =
    useColorScheme() === 'dark'
      ? navigationThemes.dark
      : navigationThemes.light;
  return (
    <ThemeProvider value={theme}>
      <Providers>
        <Bindings />
        <PushCoordinator />
        <StatusBar style="auto" />
        <Stack
          screenOptions={{
            headerTransparent: true,
            headerLargeTitle: false,
            headerBackButtonDisplayMode: 'minimal',
            headerShadowVisible: false,
            scrollEdgeEffects: softScrollEdgeEffects,
          }}
        >
          <Stack.Screen name="index" options={{ title: '' }} />
          <Stack.Screen name="debug" options={{ title: 'Debug' }} />
          <Stack.Screen name="environment" options={{ title: '运行环境' }} />
          <Stack.Screen
            name="presented/[presentationId]"
            options={({ route }) =>
              nativePresentationOptions(route.params, theme.colors.background)
            }
          />
        </Stack>
      </Providers>
    </ThemeProvider>
  );
}

function Bindings() {
  useBindSessionNav();
  useOnboardingGate();
  useEffect(() => {
    if (__DEV__) assertVendoredDomWebView();
  }, []);
  return <DiffWebViewWarmer />;
}

function Providers({ children }: PropsWithChildren) {
  if (homeVerify)
    return <HomePreviewProviders>{children}</HomePreviewProviders>;
  return (
    <AuthProvider>
      <CatalogProvider>{children}</CatalogProvider>
    </AuthProvider>
  );
}
