import { useRouter } from 'expo-router';
import { Linking } from 'react-native';
import Constants from 'expo-constants';
import { NativeGroupedList, type NativeListSection } from '@lody-ios/kit';
import { useAuth } from '@/features/auth/AuthProvider';
import { useCatalog } from '@/cloud/CatalogProvider';
import { useConnection } from '@/cloud/connection';
import { usePalette } from '@/theme/palette';
import { relativeTime } from '@/ui/time';
import { showToast } from '@/ui/toast';
import { t, tp } from '../../i18n/index.ts';

const connectionRow = {
  live: { symbol: 'circle.fill', label: 'settings.connection.live' },
  syncing: { symbol: 'circle', label: 'settings.connection.syncing' },
  offline: {
    symbol: 'xmark.octagon.fill',
    label: 'settings.connection.offline',
  },
} as const;

export default function SettingsScreen() {
  const auth = useAuth();
  const router = useRouter();
  const colors = usePalette();
  const connection = useConnection();
  const { refresh } = useCatalog();
  const shape = connectionRow[connection.state];
  const synced = connection.syncedAt
    ? relativeTime(new Date(connection.syncedAt).toISOString())
    : '';

  const sections: NativeListSection[] = [
    {
      id: 'account',
      header: t('settings.section.account'),
      rows: [
        {
          id: 'account',
          title: auth.account?.user.name ?? t('settings.account.welcome'),
          subtitle:
            auth.account?.user.email ?? t('settings.account.signInHint'),
          image: 'person.crop.circle',
          action: true,
          disclosure: true,
          navigates: true,
        },
      ],
    },
    {
      id: 'connection',
      header: t('settings.section.connection'),
      rows: [
        {
          id: 'connection',
          title: tp('settings.machineCount', connection.machines, {
            count: connection.machines,
          }),
          subtitle: [
            t(shape.label),
            connection.state === 'offline'
              ? t('settings.connection.tapToResync')
              : synced && t('settings.connection.syncedAt', { time: synced }),
          ]
            .filter(Boolean)
            .join(' · '),
          image: shape.symbol,
          action: connection.state === 'offline',
          imageTint: {
            live: colors.accent,
            offline: 'danger',
            syncing: 'secondary',
          }[connection.state],
        },
      ],
    },
    {
      id: 'about',
      header: t('settings.section.about'),
      rows: [
        {
          id: 'about',
          title: 'Lody for iOS',
          subtitle: `${Constants.expoConfig?.version ?? '0.0.0'} (${
            Constants.expoConfig?.ios?.buildNumber ?? '1'
          })`,
          image: 'info.circle',
        },
      ],
    },
    {
      id: 'credits',
      header: t('settings.section.thanks'),
      footer: t('settings.thanks.footer'),
      rows: [
        {
          id: 'credit-flowdown',
          title: 'FlowDown',
          subtitle: t('settings.thanks.flowdown'),
          image: 'arrow.up.right.square',
          action: true,
        },
      ],
    },
  ];

  if (__DEV__)
    sections.push({
      id: 'developer',
      header: t('settings.section.developer'),
      footer: t('settings.developer.footer'),
      rows: [
        {
          id: 'debug-open',
          title: 'Debug',
          image: 'ladybug',
          action: true,
          disclosure: true,
          navigates: true,
        },
      ],
    });

  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={sections}
      placeholder=""
      onRowPress={({ nativeEvent }) => {
        if (nativeEvent.id === 'debug-open') router.push('/debug');
        if (nativeEvent.id === 'account')
          router.push(auth.account ? '/settings/account' : '/');
        if (nativeEvent.id === 'connection') refresh();
        if (nativeEvent.id === 'credit-flowdown')
          void Linking.openURL('https://github.com/Lakr233/FlowDown').catch(
            () => showToast(t('settings.toast.openProjectLinkFailed')),
          );
      }}
    />
  );
}
