import { AIUsageScreen } from './AIUsageScreen';
import { AgentRolesScreen } from './AgentRolesScreen';
import { GitHubSettingsScreen } from './GitHubSettingsScreen';
import { ProjectVisibilityScreen } from './ProjectVisibilityScreen';
import { PromptShortcutsScreen } from './PromptShortcutsScreen';
import { useRouter } from 'expo-router';
import { NativeGroupedList, type NativeListSection } from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { useConnection } from '@/cloud/catalog/connection';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { t, tp } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { uiVerify } from '@/lib/uiVerify';
import { relativeTime } from '@/ui/time';
import { AboutScreen } from './AboutScreen';
import { AccountScreen } from './AccountScreen';
import { AppearanceScreen } from './AppearanceScreen';
import { ArchivedSessionsScreen } from './ArchivedSessionsScreen';
import { DiagnosticsScreen } from './DiagnosticsScreen';
import { PreferencesScreen } from './PreferencesScreen';
import { ProjectHistoryScreen } from './ProjectHistoryScreen';
import { RemoteSettingsScreen, settingsTitle } from './RemoteSettingsScreen';
import { WorkspaceEditorScreen } from './WorkspaceEditorScreen';

function View() {
  const auth = useAuth();
  const router = useRouter();
  const { push, present, cancel } = usePageRuntime();
  const colors = usePalette();
  const connection = useConnection();
  const { selected, refresh } = useCatalog();
  const workspace = auth.account ? selected : undefined;
  const sections: NativeListSection[] = [
    {
      id: 'account',
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
      id: 'personal',
      header: t('settings.section.personal'),
      rows: [
        {
          id: 'preferences',
          title: t('settings.preferences.title'),
          subtitle: t('settings.preferences.subtitle'),
          image: 'slider.horizontal.3',
          action: true,
          disclosure: true,
          navigates: true,
        },
        {
          id: 'appearance',
          title: t('settings.appearance.title'),
          subtitle: t('settings.appearance.subtitle'),
          image: 'paintpalette',
          action: true,
          disclosure: true,
          navigates: true,
        },
      ],
    },
  ];

  if (auth.account) {
    const rows: NativeListSection['rows'] = [];
    let footer: string | undefined;
    if (workspace) {
      rows.push({
        id: 'workspace-general',
        title: t('settings.workspace.general'),
        subtitle: t('settings.workspace.generalSubtitle'),
        image: 'building.2',
        action: true,
        disclosure: true,
      });
      for (const kind of ['machine', 'agent', 'mcp'] as const) {
        rows.push({
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
        });
        if (kind === 'agent')
          rows.push({
            id: 'agent-roles',
            title: t('settings.roles.title'),
            image: 'person.crop.square',
            action: true,
            disclosure: true,
            navigates: true,
          });
      }
      rows.push({
        id: 'prompt-shortcuts',
        title: t('settings.shortcuts.title'),
        image: 'doc.text',
        action: true,
        disclosure: true,
        navigates: true,
      });
      rows.push({
        id: 'project-visibility',
        title: t('settings.projects.title'),
        image: 'folder',
        action: true,
        disclosure: true,
        navigates: true,
      });
      rows.push({
        id: 'github-settings',
        title: t('settings.github.title'),
        imageAsset: 'lody-mark-github',
        action: true,
        disclosure: true,
        navigates: true,
      });
      rows.push({
        id: 'ai-usage',
        title: t('settings.aiUsage.title'),
        image: 'chart.bar.xaxis',
        action: true,
        disclosure: true,
        navigates: true,
      });
      footer = [
        t(`settings.connection.${connection.state}`),
        tp('settings.machineCount', connection.machines, {
          count: connection.machines,
        }),
        connection.syncedAt
          ? t('settings.connection.syncedAt', {
              time: relativeTime(new Date(connection.syncedAt).toISOString()),
            })
          : '',
      ]
        .filter(Boolean)
        .join(' · ');
      if (connection.state === 'offline') {
        rows.push({
          id: 'connection',
          title: t('settings.connection.resync'),
          image: 'arrow.clockwise',
          action: true,
        });
        if (connection.syncedAt)
          footer += `\n${t('settings.connection.cached')}`;
      }
    } else {
      rows.push({
        id: 'workspace-unavailable',
        title: t('settings.workspace.unavailable'),
        subtitle: t('settings.workspace.unavailableHint'),
        wrapSubtitle: true,
        image: 'building.2',
      });
    }
    sections.push({
      id: 'remote',
      header: workspace
        ? t('settings.section.workspaceNamed', { name: workspace.name })
        : t('settings.section.workspace'),
      footer,
      rows,
    });
  }

  if (workspace) {
    sections.push({
      id: 'sessions',
      header: t('settings.section.sessions'),
      rows: [
        {
          id: 'project-history',
          title: t('settings.history.title'),
          image: 'arrow.triangle.2.circlepath',
          action: true,
          disclosure: true,
          navigates: true,
        },
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
  }

  sections.push({
    id: 'other',
    header: t('settings.section.additional'),
    rows: [
      {
        id: 'about',
        title: t('settings.section.about'),
        subtitle: t('settings.about.subtitle'),
        image: 'info.circle',
        action: true,
        disclosure: true,
        navigates: true,
      },
      {
        id: 'diagnostics',
        title: t('diagnostics.title'),
        image: 'waveform.path.ecg',
        action: true,
        disclosure: true,
        navigates: true,
      },
    ],
  });

  if (__DEV__ || uiVerify) {
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
  }

  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={sections}
      placeholder=""
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'workspace-general' && workspace)
          void present(
            WorkspaceEditorScreen,
            {
              workspaceId: workspace.id,
              name: workspace.name,
              image: workspace.image,
              color: colors.accent,
            },
            { title: t('settings.workspace.general') },
          );
        for (const kind of ['machine', 'agent', 'mcp'] as const) {
          if (id === `remote-${kind}` && workspace)
            void push(
              RemoteSettingsScreen,
              { kind },
              { title: settingsTitle(kind) },
            );
        }
        if (id === 'ai-usage' && workspace) void push(AIUsageScreen);
        if (id === 'agent-roles' && workspace) void push(AgentRolesScreen);
        if (id === 'github-settings' && workspace)
          void push(GitHubSettingsScreen);
        if (id === 'project-visibility' && workspace)
          void push(ProjectVisibilityScreen);
        if (id === 'prompt-shortcuts' && workspace)
          void push(PromptShortcutsScreen);
        if (id === 'preferences') void push(PreferencesScreen);
        if (id === 'appearance') void push(AppearanceScreen);
        if (id === 'about') void push(AboutScreen);
        if (id === 'project-history' && workspace)
          void push(ProjectHistoryScreen);
        if (id === 'archived' && workspace) void push(ArchivedSessionsScreen);
        if (id === 'diagnostics') void push(DiagnosticsScreen);
        if (id === 'account' && auth.account) void push(AccountScreen);
        if (id === 'connection' && workspace && connection.state === 'offline')
          refresh();
        if (id === 'debug-open') {
          cancel();
          router.push('/debug');
        }
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
