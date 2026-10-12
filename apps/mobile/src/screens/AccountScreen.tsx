import { useEffect } from 'react';
import { Alert } from 'react-native';
import { NativeGroupedList } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePalette } from '@/lib/theme/palette';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { t } from '../lib/i18n/index.ts';
import { TeamScreen } from './TeamScreen';
import { TeamJoinScreen } from './TeamJoinScreen';
function View() {
  const auth = useAuth();
  const { selected } = useCatalog();
  const colors = usePalette();
  const { cancel, push } = usePageRuntime();
  useEffect(() => {
    if (!auth.account) cancel();
  }, [auth.account, cancel]);
  const signOutTitle = t(auth.busy ? 'account.signingOut' : 'account.signOut');
  return (
    <>
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
                      image: auth.account.user.image ?? 'person.crop.circle',
                    },
                  ],
                },
                {
                  id: 'team',
                  rows: [
                    {
                      id: 'team',
                      title: t('team.title'),
                      subtitle: selected?.name,
                      image: 'person.2',
                      action: !!selected,
                      disclosure: !!selected,
                      navigates: !!selected,
                    },
                    {
                      id: 'team-join',
                      title: t('team.joinWorkspace'),
                      image: 'person.badge.plus',
                      action: true,
                      disclosure: true,
                      navigates: true,
                    },
                  ],
                },
                {
                  id: 'logout',
                  footer: auth.error ?? undefined,
                  rows: [
                    {
                      id: 'logout',
                      title: signOutTitle,
                      destructive: true,
                      action: !auth.busy,
                    },
                  ],
                },
              ]
            : []
        }
        onRowPress={({ nativeEvent: { id } }) => {
          if (id === 'team' && auth.account && selected) {
            void push(TeamScreen, {
              userId: auth.account.user.id,
              workspaceId: selected.id,
              workspaceName: selected.name,
            });
            return;
          }
          if (id === 'team-join' && auth.account) {
            void push(TeamJoinScreen, { userId: auth.account.user.id });
            return;
          }
          if (id !== 'logout') return;
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
          );
        }}
      />
    </>
  );
}
export const AccountScreen = definePage({
  id: 'account',
  title: t('account.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
