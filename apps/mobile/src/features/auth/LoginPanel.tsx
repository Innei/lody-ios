import { ActivityIndicator, Image, Pressable, Text, View } from 'react-native';
import { usePalette } from '@/theme/palette';
import { useAuth } from './AuthProvider';
import { Button } from '@/ui/Button';
import { t } from '../../i18n/index.ts';
export function LoginPanel() {
  const auth = useAuth(),
    colors = usePalette();
  return (
    <View style={{ gap: 24, paddingTop: 20 }}>
      <Image
        accessibilityIgnoresInvertColors
        accessible
        accessibilityLabel="Lody"
        source={require('../../../assets/logo.png')}
        style={{ width: 56, height: 56 }}
      />
      <View style={{ gap: 12 }}>
        <Text
          style={{
            color: colors.label,
            fontSize: 24,
            fontWeight: '700',
            lineHeight: 32,
            letterSpacing: -0.7,
          }}
        >
          {t('login.headline')}
        </Text>
        <Text
          style={{ color: colors.secondaryLabel, fontSize: 16, lineHeight: 25 }}
        >
          {t('login.subhead')}
        </Text>
      </View>
      {auth.code ? (
        <View
          style={{
            padding: 20,
            borderRadius: 20,
            backgroundColor: colors.card,
            gap: 12,
          }}
        >
          <Text style={{ color: colors.secondaryLabel }}>
            {t('login.verifyCode')}
          </Text>
          <Text
            selectable
            style={{
              color: colors.label,
              fontFamily: 'Menlo',
              fontSize: 28,
              fontWeight: '600',
            }}
          >
            {auth.code.user_code}
          </Text>
          <Button onPress={() => void auth.reopen()}>
            {t('login.reopen')}
          </Button>
        </View>
      ) : null}
      {auth.busy ? (
        <View style={{ gap: 12, alignItems: 'center' }}>
          <ActivityIndicator color={colors.accent} />
          <Text style={{ color: colors.secondaryLabel }}>
            {t(auth.code ? 'login.waiting' : 'login.connecting')}
          </Text>
          <Button testID="auth-cancel" onPress={auth.cancel}>
            {t('common.cancel')}
          </Button>
        </View>
      ) : (
        <Pressable
          testID="auth-login"
          accessibilityRole="button"
          onPress={() => void auth.login()}
          style={{
            minHeight: 54,
            backgroundColor: colors.accent,
            borderRadius: 16,
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <Text
            style={{ color: colors.onAccent, fontSize: 17, fontWeight: '600' }}
          >
            {t('login.connect')}
          </Text>
        </Pressable>
      )}
      <Text
        style={{ color: colors.secondaryLabel, fontSize: 12, lineHeight: 19 }}
      >
        {t('login.footnote')}
      </Text>
      {auth.error ? (
        <View>
          <Text style={{ color: colors.danger, lineHeight: 22 }}>
            {auth.error}
          </Text>
          <Button onPress={() => void auth.restore()}>
            {t('login.retry')}
          </Button>
        </View>
      ) : null}
    </View>
  );
}
