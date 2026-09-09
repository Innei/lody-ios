import { NotificationSettingsScreen } from '@/screens/NotificationSettingsScreen';
import { useRouter } from 'expo-router';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { AccountScreen } from './AccountScreen';
import { ArchivedSessionsScreen } from './ArchivedSessionsScreen';
import { LicensesScreen } from './LicensesScreen';
import { RemoteSettingsScreen, settingsTitle } from './RemoteSettingsScreen';
import { Linking } from 'react-native';
import Constants from 'expo-constants';
import { NativeGroupedList, type NativeListSection } from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { useConnection } from '@/cloud/catalog/connection';
import { usePalette } from '@/lib/theme/palette';
import { relativeTime } from '@/ui/time';
import { showToast } from '@/ui/toast';
import { definePage } from '@/lib/presentation';
import type { RemoteSetting } from '@/models/settings';
import { t, tp } from '../lib/i18n/index.ts';

const connectionRow = {
  live: { symbol: 'circle.fill', label: 'settings.connection.live' },
  syncing: { symbol: 'circle', label: 'settings.connection.syncing' },
  offline: {
    symbol: 'xmark.octagon.fill',
    label: 'settings.connection.offline',
  },
} as const;

function View() {
  const auth = useAuth();
  const router = useRouter();
  const { push, cancel } = usePageRuntime();
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
          image: auth.account?.user.image ?? 'person.crop.circle',
          action: !!auth.account,
          disclosure: !!auth.account,
          navigates: !!auth.account,
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
      id: 'notifications',
      rows: [
        {
          id: 'notifications',
          title: '通知',
          image: 'bell',
          action: true,
          disclosure: true,
          navigates: true,
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
        {
          id: 'licenses',
          title: t('settings.licenses.title'),
          image: 'doc.text',
          action: true,
          disclosure: true,
          navigates: true,
        },
      ],
    },
  ];

  if (auth.account)
    sections.splice(1, 0, {
      id: 'remote',
      header: t('settings.remote.title'),
      rows: (['machine', 'agent', 'mcp'] as const).map((kind) => ({
        id: `remote-${kind}`,
        title: t(`settings.remote.${kind}`),
        image: {
          machine: 'desktopcomputer',
          agent: 'sparkles',
          mcp: 'puzzlepiece.extension',
        }[kind],
        action: true,
        disclosure: true,
        navigates: true,
      })),
    });
  if (auth.account)
    sections.splice(1, 0, {
      id: 'sessions',
      header: t('settings.section.sessions'),
      rows: [
        {
          id: 'archived',
          title: t('settings.archived.title'),
          image: 'archivebox',
          action: true,
          disclosure: true,
          navigates: true,
        },
      ],
    });

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
        if (nativeEvent.id.startsWith('remote-')) {
          const kind = nativeEvent.id.slice(7) as RemoteSetting['kind'];
          void push(
            RemoteSettingsScreen,
            { kind },
            { title: settingsTitle(kind) },
          );
        }
        if (nativeEvent.id === 'notifications')
          void push(NotificationSettingsScreen, {});
        if (nativeEvent.id === 'archived') void push(ArchivedSessionsScreen);
        if (nativeEvent.id === 'licenses') void push(LicensesScreen);
        if (nativeEvent.id === 'debug-open') {
          cancel();
          router.push('/debug');
        }
        if (nativeEvent.id === 'account' && auth.account)
          void push(AccountScreen);
        if (nativeEvent.id === 'connection') refresh();
        if (nativeEvent.id === 'credit-flowdown')
          void Linking.openURL('https://github.com/Lakr233/FlowDown').catch(
            () => showToast(t('settings.toast.openProjectLinkFailed')),
          );
      }}
    />
  );
}

export const SettingsScreen = definePage({
  id: 'settings',
  title: t('tabs.settings'),
  Component: View,
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
