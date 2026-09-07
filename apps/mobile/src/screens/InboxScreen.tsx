import { Stack } from 'expo-router';
import { useMemo, useState } from 'react';
import {
  NativeGroupedList,
  NativeTitleMenu,
  initialInboxView,
  saveInboxView,
  readInboxExpansion,
  saveInboxExpansion,
} from '@lody-ios/kit';
import {
  ActivityIndicator,
  Image,
  Pressable,
  Text,
  View as RNView,
} from 'react-native';
import { Screen } from '@/ui/Screen';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePalette } from '@/theme/palette';
import { Button } from '@/ui/Button';
import { listPlaceholder, searchPlaceholder } from '@/ui/listState';
import {
  inboxSections,
  projectSections,
  searchSections,
} from '@/features/sessions/inbox';
import { openCatalogRow } from '@/hooks/screens/openCatalogRow';
import { sessionRowAction } from '@/features/sessions/sessionActions';
import { definePage, present } from '@/presentation';
import { showToast } from '@/ui/toast';
import { t } from '../i18n/index.ts';
import { InboxSettingsScreen } from './InboxSettingsScreen';

function View() {
  const { account, localReady } = useAuth();
  const colors = usePalette();
  const { catalog, selected, setWorkspaceId, loading, connected, refresh } =
    useCatalog();
  const [mode, setMode] = useState(initialInboxView);
  const [expanded, setExpanded] = useState(readInboxExpansion);
  const [query, setQuery] = useState('');
  const searching = !!query.trim();
  const sections = useMemo(
    () =>
      mode === 0
        ? projectSections(catalog, colors.accent, expanded)
        : inboxSections(catalog, { accent: colors.accent }),
    [mode, catalog, colors.accent, expanded],
  );
  if (!localReady) return <Screen />;
  if (!account)
    return (
      <Screen>
        <Login />
      </Screen>
    );
  return (
    <>
      <Stack.Screen options={{ title: selected?.name ?? t('tabs.sessions') }} />
      <Stack.SearchBar
        placement="stacked"
        placeholder={t('search.field.placeholder')}
        hideWhenScrolling={false}
        onChangeText={({ nativeEvent }) => setQuery(nativeEvent.text)}
        onCancelButtonPress={() => setQuery('')}
      />
      <Stack.Title asChild>
        <NativeTitleMenu
          accessibilityName={t('inbox.workspaceSwitch.accessibility', {
            name: selected?.name ?? t('common.workspace'),
          })}
          label={selected?.name ?? t('common.workspace')}
          items={account.workspaces.map((workspace) => ({
            id: workspace.id,
            title: workspace.name,
            selected: workspace.id === selected?.id,
          }))}
          onSelect={setWorkspaceId}
        />
      </Stack.Title>
      <Stack.Toolbar placement="right">
        <Stack.Toolbar.Button
          accessibilityLabel={t('inbox.settings.accessibility')}
          icon="slider.horizontal.3"
          tintColor={colors.accent}
          onPress={async () => {
            try {
              const result = await present(InboxSettingsScreen, { mode });
              if (result.status === 'completed') {
                setMode(result.value);
                saveInboxView(result.value);
              }
            } catch {
              showToast(t('inbox.toast.settingsFailed'));
            }
          }}
        />
      </Stack.Toolbar>
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        sections={
          searching ? searchSections(catalog, query, colors.accent) : sections
        }
        refreshing={false}
        placeholder={
          searching
            ? searchPlaceholder({ signedIn: true, query, loading, connected })
            : listPlaceholder({ loading, connected })
        }
        onRefresh={refresh}
        contentStyle
        onRowPress={({ nativeEvent: { id } }) => {
          if (id.startsWith('toggle:')) {
            const projectId = id.slice(7);
            const next = !(expanded[projectId] ?? true);
            saveInboxExpansion(projectId, next);
            setExpanded((previous) => ({ ...previous, [projectId]: next }));
          } else openCatalogRow(id, catalog);
        }}
        onRowAction={({ nativeEvent: { id, actionId } }) => {
          if (selected) sessionRowAction(selected.id, catalog, id, actionId);
        }}
      />
    </>
  );
}

export const InboxScreen = definePage({
  id: 'inbox',
  title: t('tabs.sessions'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});

function Login() {
  const auth = useAuth();
  const colors = usePalette();
  return (
    <RNView style={{ gap: 24, paddingTop: 20 }}>
      <Image
        accessibilityIgnoresInvertColors
        accessible
        accessibilityLabel="Lody"
        source={require('../../assets/logo.png')}
        style={{ width: 56, height: 56 }}
      />
      <RNView style={{ gap: 12 }}>
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
      </RNView>
      {auth.code ? (
        <RNView
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
        </RNView>
      ) : null}
      {auth.busy ? (
        <RNView style={{ gap: 12, alignItems: 'center' }}>
          <ActivityIndicator color={colors.accent} />
          <Text style={{ color: colors.secondaryLabel }}>
            {t(auth.code ? 'login.waiting' : 'login.connecting')}
          </Text>
          <Button testID="auth-cancel" onPress={auth.cancel}>
            {t('common.cancel')}
          </Button>
        </RNView>
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
        <RNView>
          <Text style={{ color: colors.danger, lineHeight: 22 }}>
            {auth.error}
          </Text>
          <Button onPress={() => void auth.restore()}>
            {t('login.retry')}
          </Button>
        </RNView>
      ) : null}
    </RNView>
  );
}
