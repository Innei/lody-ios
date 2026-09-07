import { useEffect } from 'react';
import { Alert } from 'react-native';
import { NativeGroupedList } from '@lody-ios/kit';
import { definePage } from '@/presentation';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { usePalette } from '@/theme/palette';
import { Stack, useRouter } from 'expo-router';
import { t } from '../../i18n/index.ts';
function AccountScreen() {
  const auth = useAuth();
  const colors = usePalette();
  const router = useRouter();
  useEffect(() => {
    if (!auth.account) router.replace('/');
  }, [auth.account, router]);
  return (
    <>
      <Stack.Screen options={{ title: t('account.title') }} />
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        placeholder={t('account.placeholder')}
        sections={
          auth.account
            ? [
                {
                  id: 'account',
                  rows: [
                    {
                      id: 'name',
                      title: auth.account.user.name,
                      subtitle: auth.account.user.email,
                      image: 'person.crop.circle',
                    },
                  ],
                },
                {
                  id: 'logout',
                  footer: auth.error ?? undefined,
                  rows: [
                    {
                      id: 'logout',
                      title: t(
                        auth.busy ? 'account.signingOut' : 'account.signOut',
                      ),
                      destructive: true,
                      action: !auth.busy,
                    },
                  ],
                },
              ]
            : []
        }
        onRowPress={() =>
          Alert.alert(
            t('account.signOutConfirm.title'),
            t('account.signOutConfirm.message'),
            [
              { text: t('common.cancel'), style: 'cancel' },
              {
                text: t('account.signOut'),
                style: 'destructive',
                onPress: () => {
                  void auth.logout();
                },
              },
            ],
          )
        }
      />
    </>
  );
}
export const accountPage = definePage({
  id: 'account',
  title: t('account.title'),
  Component: AccountScreen,
});
