import { useCallback, useMemo, useRef, useState } from 'react';
import {
  Alert,
  StyleSheet,
  Switch,
  TextInput,
  View as RNView,
} from 'react-native';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import { Screen } from '@/ui/Screen';
import { AppText } from '@/ui/AppText';
import { FormGroup, formInputStyle } from '@/ui/FormGroup';
import { Button } from '@/ui/Button';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { showToast } from '@/ui/toast';
import type { RemoteSetting } from '@lody/cloud-runtime/models/settings';
import type { SettingsService } from './RemoteSettingsScreen';
import { t } from '../lib/i18n/index.ts';

type Params = {
  workspaceId: string;
  item: RemoteSetting;
  service: SettingsService;
};

function View() {
  const { params, finish, cancel } = usePageRuntime<Params>();
  const { item, workspaceId, service } = params;
  const colors = usePalette();
  const [name, setName] = useState(item.name);
  const [prompt, setPrompt] = useState(item.prompt ?? '');
  const [enabledByDefault, setEnabled] = useState(
    item.enabledByDefault === true,
  );
  const [busy, setBusy] = useState(false);
  const [failure, setFailure] = useState('');
  const saving = useRef(false);
  const inputStyle = [formInputStyle, { color: colors.label }];
  const reportError = useCallback(
    (cause: unknown) => {
      const message =
        cause instanceof Error
          ? cause.message
          : t('settings.remote.saveFailed');
      setFailure(message);
      if (item.kind !== 'mcp') showToast(message, 'error');
    },
    [item.kind],
  );
  const save = useCallback(async () => {
    if (saving.current || item.readOnly || !name.trim()) return;
    saving.current = true;
    setBusy(true);
    setFailure('');
    try {
      await service({
        workspaceId,
        kind: item.kind,
        edit: {
          item,
          name,
          ...(item.kind === 'agent' ? { prompt } : {}),
          ...(item.kind === 'mcp' ? { enabledByDefault } : {}),
        },
      });
      finish();
    } catch (cause) {
      reportError(cause);
    } finally {
      saving.current = false;
      setBusy(false);
    }
  }, [
    name,
    prompt,
    enabledByDefault,
    workspaceId,
    item,
    service,
    finish,
    reportError,
  ]);
  const remove = async () => {
    if (saving.current || item.readOnly) return;
    saving.current = true;
    setBusy(true);
    setFailure('');
    try {
      await service({ workspaceId, kind: 'mcp', remove: item });
      finish();
    } catch (cause) {
      reportError(cause);
    } finally {
      saving.current = false;
      setBusy(false);
    }
  };
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('settings.remote.save'),
        accessibilityLabel: t('settings.remote.save'),
        variant: 'prominent' as const,
        tintColor: colors.accent,
        disabled: busy || !name.trim(),
        onPress: () => void save(),
      },
    ],
    [busy, name, save, colors.accent],
  );
  const dismiss = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('common.cancel'),
        accessibilityLabel: t('common.cancel'),
        disabled: busy,
        onPress: cancel,
      },
    ],
    [busy, cancel],
  );
  useSheetHeader(actions, dismiss);
  return (
    <Screen
      automaticallyAdjustKeyboardInsets
      style={{ backgroundColor: colors.background }}
    >
      <FormGroup
        header={t('settings.remote.name')}
        footer={
          item.kind === 'machine' ? t('settings.remote.machineHint') : undefined
        }
      >
        <TextInput
          testID="setting-name"
          accessibilityLabel={t('settings.remote.name')}
          style={inputStyle}
          value={name}
          onChangeText={setName}
          editable={!busy}
          maxLength={200}
          autoCorrect={false}
          returnKeyType="done"
          clearButtonMode="while-editing"
        />
      </FormGroup>
      {item.kind === 'mcp' && failure ? (
        <AppText
          testID="setting-error"
          accessibilityRole="alert"
          style={{
            color: colors.danger,
            marginHorizontal: 16,
            marginBottom: 12,
          }}
        >
          {failure}
        </AppText>
      ) : null}
      {item.kind === 'agent' && (
        <FormGroup
          header={t('settings.remote.prompt')}
          footer={t('settings.remote.agentHint')}
        >
          <TextInput
            testID="setting-prompt"
            accessibilityLabel={t('settings.remote.prompt')}
            style={[inputStyle, styles.prompt]}
            multiline
            scrollEnabled={false}
            value={prompt}
            onChangeText={setPrompt}
            editable={!busy}
            maxLength={32000}
          />
        </FormGroup>
      )}
      {item.kind === 'mcp' && (
        <FormGroup
          footer={
            item.configured === false
              ? t('settings.mcp.missingConnection')
              : t('settings.remote.mcpHint')
          }
        >
          <RNView style={styles.toggleRow}>
            <AppText style={styles.toggleLabel}>
              {t('settings.remote.default')}
            </AppText>
            <Switch
              testID="setting-enabled"
              accessibilityLabel={t('settings.remote.default')}
              trackColor={{ true: colors.accent }}
              value={enabledByDefault}
              onValueChange={setEnabled}
              disabled={
                busy || (item.configured === false && !enabledByDefault)
              }
            />
          </RNView>
        </FormGroup>
      )}
      {item.kind === 'mcp' && !item.readOnly && (
        <FormGroup footer={t('settings.mcp.connectionEditing')}>
          <Button
            testID="setting-delete"
            label={t('settings.mcp.delete')}
            destructive
            disabled={busy}
            onPress={() =>
              Alert.alert(
                t('settings.mcp.delete'),
                t('settings.mcp.deleteHint', { name: item.name }),
                [
                  { text: t('common.cancel'), style: 'cancel' },
                  {
                    text: t('common.delete'),
                    style: 'destructive',
                    onPress: () => void remove(),
                  },
                ],
              )
            }
          />
        </FormGroup>
      )}
    </Screen>
  );
}
export const RemoteSettingEditorScreen = definePage<Params>({
  id: 'remote-setting-editor',
  title: t('settings.remote.edit'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from remote settings');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});

const styles = StyleSheet.create({
  prompt: { minHeight: 176, paddingTop: 12, textAlignVertical: 'top' },
  toggleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 16,
    minHeight: 44,
    paddingHorizontal: 16,
    paddingVertical: 6,
  },
  toggleLabel: { flex: 1 },
});
