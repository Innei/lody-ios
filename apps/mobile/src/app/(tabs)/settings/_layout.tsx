import { Stack } from 'expo-router';
import { softScrollEdgeEffects } from '@/ui/Screen';
import { t } from '../../../i18n/index.ts';
export default function Layout() {
  return (
    <Stack
      screenOptions={{
        headerTransparent: true,
        headerShadowVisible: false,
        scrollEdgeEffects: softScrollEdgeEffects,
      }}
    >
      <Stack.Screen
        name="index"
        options={{ title: t('tabs.settings'), headerLargeTitle: false }}
      />
    </Stack>
  );
}
