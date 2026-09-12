import { useEffect } from 'react';
import {
  ActivityIndicator,
  Image,
  Platform,
  ScrollView,
  View as RNView,
} from 'react-native';
import Animated, { FadeInUp, useReducedMotion } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import {
  NativeGlassSurface,
  NativePressable,
  NativeSymbol,
} from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { t } from '../lib/i18n/index.ts';

const features = [
  { id: 'sessions', symbol: 'bubble.left.and.text.bubble.right.fill' },
  { id: 'reply', symbol: 'paperplane.fill' },
  { id: 'privacy', symbol: 'lock.shield.fill' },
] as const;

function useRise() {
  const reduced = useReducedMotion();
  return (step: number) =>
    reduced
      ? undefined
      : FadeInUp.delay(300 + step * 90)
          .duration(500)
          .withInitialValues({ transform: [{ translateY: 14 }] });
}

function View() {
  const auth = useAuth();
  const { finish } = usePageRuntime();
  const colors = usePalette();
  const insets = useSafeAreaInsets();
  const rise = useRise();
  useEffect(() => {
    if (auth.account) finish();
  }, [auth.account, finish]);
  const waiting = auth.busy || !!auth.code;
  return (
    <RNView style={{ flex: 1 }} testID="onboarding-sheet">
      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{
          flexGrow: 1,
          paddingHorizontal: 28,
          paddingTop: 48,
          paddingBottom: 24,
          gap: 36,
        }}
      >
        <Animated.View
          entering={rise(0)}
          style={{ alignItems: 'center', gap: 14 }}
        >
          <Image
            accessibilityIgnoresInvertColors
            source={require('../../assets/logo.png')}
            style={{
              width: 64,
              height: 64,
              borderRadius: 15,
            }}
          />
          <AppText
            accessibilityRole="header"
            style={{
              fontSize: 30,
              lineHeight: 36,
              fontWeight: '700',
              letterSpacing: -0.6,
              textAlign: 'center',
            }}
          >
            {t('onboarding.title')}
          </AppText>
        </Animated.View>
        {waiting ? (
          <Waiting />
        ) : (
          <RNView style={{ gap: 24 }}>
            {features.map((feature, index) => (
              <Animated.View
                key={feature.id}
                entering={rise(index + 1)}
                accessible
                style={{ flexDirection: 'row', gap: 16 }}
              >
                <NativeSymbol
                  symbol={feature.symbol}
                  pointSize={28}
                  tint={colors.accent}
                  style={{ width: 36, height: 36, marginTop: 2 }}
                />
                <RNView style={{ flex: 1, gap: 2 }}>
                  <AppText style={{ fontWeight: '600' }}>
                    {t(`onboarding.${feature.id}.title`)}
                  </AppText>
                  <AppText variant="secondary">
                    {t(`onboarding.${feature.id}.body`)}
                  </AppText>
                </RNView>
              </Animated.View>
            ))}
          </RNView>
        )}
      </ScrollView>
      <RNView
        style={{
          paddingHorizontal: 24,
          paddingBottom: Math.max(insets.bottom, 16),
          gap: 14,
        }}
      >
        {waiting ? null : (
          <Animated.View entering={rise(4)}>
            {auth.error ? (
              <AppText
                variant="secondary"
                accessibilityLiveRegion="polite"
                style={{ color: colors.danger, textAlign: 'center' }}
              >
                {auth.error}
              </AppText>
            ) : (
              <RNView
                style={{ alignItems: 'center', gap: 8, paddingHorizontal: 14 }}
              >
                <NativeSymbol
                  symbol="person.2.fill"
                  pointSize={20}
                  tint={colors.accent}
                  style={{ width: 24, height: 24 }}
                />
                <AppText
                  variant="meta"
                  style={{ fontSize: 12, lineHeight: 17, textAlign: 'center' }}
                >
                  {t('login.footnote')}
                </AppText>
              </RNView>
            )}
          </Animated.View>
        )}
        {waiting ? (
          <SheetButton key="cancel" testID="auth-cancel" onPress={auth.cancel}>
            {t('common.cancel')}
          </SheetButton>
        ) : (
          <SheetButton
            key="connect"
            primary
            testID="onboarding-connect"
            onPress={() => void auth.login()}
          >
            {t(auth.error ? 'login.retry' : 'login.connect')}
          </SheetButton>
        )}
      </RNView>
    </RNView>
  );
}

function Waiting() {
  const auth = useAuth();
  const colors = usePalette();
  return (
    <RNView style={{ gap: 28 }}>
      {auth.code ? (
        <RNView
          style={{
            padding: 20,
            borderRadius: 16,
            borderCurve: 'continuous',
            backgroundColor: colors.fill,
            gap: 10,
          }}
        >
          <AppText variant="secondary">{t('login.verifyCode')}</AppText>
          <AppText
            selectable
            testID="onboarding-code"
            variant="mono"
            style={{ fontSize: 28, lineHeight: 34, fontWeight: '600' }}
          >
            {auth.code.user_code}
          </AppText>
          <Button
            style={{ alignItems: 'flex-start' }}
            onPress={() => void auth.reopen()}
          >
            {t('login.reopen')}
          </Button>
        </RNView>
      ) : null}
      <RNView
        style={{
          flexDirection: 'row',
          justifyContent: 'center',
          alignItems: 'center',
          gap: 10,
        }}
      >
        <ActivityIndicator color={colors.secondaryLabel} />
        <AppText variant="secondary">
          {t(auth.code ? 'login.waiting' : 'login.connecting')}
        </AppText>
      </RNView>
    </RNView>
  );
}

function SheetButton({
  children,
  onPress,
  primary = false,
  testID,
}: {
  children: string;
  onPress: () => void;
  primary?: boolean;
  testID?: string;
}) {
  const colors = usePalette();
  return (
    <NativePressable
      testID={testID}
      accessibilityLabel={children}
      onPress={onPress}
      style={{ minHeight: 52, alignItems: 'center', justifyContent: 'center' }}
    >
      <NativeGlassSurface radius={26} tint={primary ? colors.accent : ''} />
      <AppText
        style={{
          color: primary ? colors.onAccent : colors.accent,
          fontWeight: '600',
        }}
      >
        {children}
      </AppText>
    </NativePressable>
  );
}

export const OnboardingScreen = definePage({
  id: 'onboarding',
  title: t('onboarding.title'),
  Component: View,
  presentation: {
    style: Platform.OS === 'ios' && Platform.isPad ? 'formSheet' : 'pageSheet',
    dismissible: false,
    headerShown: false,
  },
});
