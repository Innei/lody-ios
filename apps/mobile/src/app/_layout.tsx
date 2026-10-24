import {
  homeVerify,
  HomePreviewProviders,
} from '@/screens/debug/HomePreviewScreen';
import { type PropsWithChildren, useEffect, useMemo } from 'react';
import { PushCoordinator } from '@/features/notifications/PushCoordinator';
import { ShareSnapshot } from '@/features/share/ShareSnapshot';
import { ShareCoordinator } from '@/features/share/ShareCoordinator';
import { Stack, ThemeProvider } from 'expo-router';
import { CatalogProvider } from '@/cloud/catalog/CatalogProvider';
import { AuthProvider } from '@/cloud/auth/AuthProvider';
import { StatusBar } from 'expo-status-bar';
import { Dimensions, StyleSheet, useColorScheme } from 'react-native';
import { nativePresentationOptions } from '@/lib/presentation';
import { navigationThemes, usePalette } from '@/lib/theme/palette';
import { useAppearance } from '@/lib/theme/appearance';
import { softDarkBackground } from '@/lib/theme/tokens';
import { NativeLayoutProbe, navigationScrollEdgeEffects } from '@lody-ios/kit';
import { useBindSessionNav } from '@/hooks/screens/useBindSessionNav';
import { useOnboardingGate } from '@/hooks/screens/useOnboardingGate';
import { assertVendoredDomWebView } from '@/lib/assert-vendored-dom-webview';
import { SettingsBaselineProviders } from '@/screens/debug/settingsBaseline';
import { uiVerify } from '@/lib/uiVerify';
import {
  guessLayoutTraits,
  setLayoutTraits,
} from '@/lib/presentation/layoutMode';

export const unstable_settings = { initialRouteName: 'index' };

const initialWindow = Dimensions.get('window');
setLayoutTraits(guessLayoutTraits(initialWindow.width, initialWindow.height));

export default function RootLayout() {
  const colorScheme = useColorScheme();
  const { darkBackground } = useAppearance();
  const colors = usePalette();
  const theme = useMemo(() => {
    const base =
      colorScheme === 'dark' ? navigationThemes.dark : navigationThemes.light;
    return {
      ...base,
      colors: {
        ...base.colors,
        primary: colors.accent,
        background:
          colorScheme === 'dark' && darkBackground === 'soft'
            ? softDarkBackground
            : base.colors.background,
      },
    };
  }, [colorScheme, darkBackground, colors.accent]);
  return (
    <ThemeProvider value={theme}>
      <Providers>
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
  return null;
}

function Providers({ children }: PropsWithChildren) {
  if (homeVerify)
    return <HomePreviewProviders>{children}</HomePreviewProviders>;
  return (
    <AuthProvider>
      <CatalogProvider>
        {uiVerify ? (
          <SettingsBaselineProviders>{children}</SettingsBaselineProviders>
        ) : (
          children
        )}
      </CatalogProvider>
    </AuthProvider>
  );
}
