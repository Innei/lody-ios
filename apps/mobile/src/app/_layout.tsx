import { homeVerify, HomePreviewProviders } from '@/features/debug/HomePreview';
import type { PropsWithChildren } from 'react';
import { Stack, ThemeProvider } from 'expo-router';
import { CatalogProvider } from '@/cloud/catalog/CatalogProvider';
import { AuthProvider } from '@/cloud/auth/AuthProvider';
import { StatusBar } from 'expo-status-bar';
import { useColorScheme } from 'react-native';
import { nativePresentationOptions } from '@/presentation';
import { navigationThemes } from '@/theme/palette';
import { softScrollEdgeEffects } from '@/ui/Screen';

export const unstable_settings = { initialRouteName: '(tabs)' };

export default function RootLayout() {
  const theme =
    useColorScheme() === 'dark'
      ? navigationThemes.dark
      : navigationThemes.light;
  return (
    <ThemeProvider value={theme}>
      <Providers>
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
          <Stack.Screen name="index" options={{ headerShown: false }} />
          <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
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

function Providers({ children }: PropsWithChildren) {
  if (homeVerify)
    return <HomePreviewProviders>{children}</HomePreviewProviders>;
  return (
    <AuthProvider>
      <CatalogProvider>{children}</CatalogProvider>
    </AuthProvider>
  );
}
