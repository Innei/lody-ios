import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Alert,
  StyleSheet,
  Switch,
  TextInput,
  View as RNView,
} from 'react-native';
import { NativeNavigationHeader } from '@lody-ios/kit';
import type {
  ProviderCapability,
  ProviderConfig,
  ProviderMachine,
  ProviderService,
  ProviderSummary,
} from '@lody/cloud-runtime/models/providers';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import {
  connectionKeys,
  parseProviderEnvironment,
  providerError,
  providerStatus,
  providerTypeLabel,
  queueProvider,
  runtimeOverrideKey,
} from '@/features/providers/provider-config';
import { usePalette } from '@/lib/theme/palette';
import { Screen } from '@/ui/Screen';
import { FormGroup, formInputStyle } from '@/ui/FormGroup';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { showToast } from '@/ui/toast';
import { t } from '@/lib/i18n';
import { ProviderOperationScreen } from './ProviderOperationScreen';

type Params = {
  workspaceId: string;
  machine: ProviderMachine;
  service: ProviderService;
  item?: ProviderSummary;
  draft?: ProviderConfig;
};

function View() {
  const { params, present, finish, cancel } = usePageRuntime<Params>();
  const { workspaceId, machine, service, item } = params;
  const colors = usePalette();
  const [config, setConfig] = useState<ProviderConfig | undefined>(
    params.draft,
  );
  const [envText, setEnvText] = useState('');
  const [apiKey, setApiKey] = useState('');
  const [baseURL, setBaseURL] = useState('');
  const [args, setArgs] = useState('[]');
  const [extensions, setExtensions] = useState('');
  const [titleOptions, setTitleOptions] = useState('{}');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(!params.draft);
  const [overLimit, setOverLimit] = useState(item?.overLimit === true);
  const [error, setError] = useState('');
  const [runtime, setRuntime] = useState('');
  const [verified, setVerified] = useState('');
  const [capability, setCapability] = useState<ProviderCapability>();
  const revision = useRef<string | undefined>(undefined);
  const persisted = useRef<
    { request: string; config: ProviderConfig } | undefined
  >(undefined);
  const saving = useRef(false);
  const mounted = useRef(true);
  const inputStyle = [formInputStyle, { color: colors.label }];
  const multiline = [inputStyle, styles.multiline];
  const hydrate = useCallback((value: ProviderConfig, rev?: string) => {
    setConfig(value);
    revision.current = rev;
    persisted.current = rev
      ? { request: JSON.stringify(value), config: value }
      : undefined;
    const keys = connectionKeys(value);
    const env = { ...value.env };
    if (keys) {
      setApiKey(env[keys.key] ?? '');
      setBaseURL(env[keys.url] ?? '');
      delete env[keys.key];
      delete env[keys.url];
    }
    setEnvText(
      Object.entries(env)
        .map(([key, value]) => `${key}=${value}`)
        .join('\n'),
    );
    setArgs(JSON.stringify(value.customAcp?.args ?? []));
    setExtensions(value.runtimeOverrides?.piExtensions?.join('\n') ?? '');
    setTitleOptions(
      JSON.stringify(value.titleGeneration?.configOptionValues ?? {}, null, 2),
    );
  }, []);
  const load = useCallback(async () => {
    if (!item) return;
    setLoading(true);
    try {
      const reply = await service({
        action: 'get',
        workspaceId,
        machineId: machine.id,
        id: item.id,
      });
      if (!mounted.current) return;
      if (!reply.config) throw new Error('invalid_provider_response');
      setOverLimit(reply.overLimit === true);
      if (reply.overLimit) setConfig(reply.config);
      else hydrate(reply.config, reply.revision);
      setError('');
    } catch (cause) {
      if (mounted.current) setError(providerError(cause));
    } finally {
      if (mounted.current) setLoading(false);
    }
  }, [item, service, workspaceId, machine.id, hydrate]);
  useEffect(() => {
    mounted.current = true;
    if (params.draft) hydrate(params.draft);
    else void load();
    return () => {
      mounted.current = false;
    };
  }, [params.draft, load, hydrate]);
  const identity = JSON.stringify([
    config?.cliType,
    config?.agentType,
    config?.customAcp,
    config?.runtimeOverrides,
    config?.codexAuth,
    envText,
    apiKey,
    baseURL,
    args,
    extensions,
  ]);
  const build = () => {
    if (overLimit) throw new Error(t('providers.overLimit'));
    if (!config || !config.name.trim()) throw new Error(t('providers.invalid'));
    const next: ProviderConfig = {
      ...config,
      env: parseProviderEnvironment(envText),
    };
    const keys = connectionKeys(config);
    if (keys) {
      if (apiKey.trim()) next.env[keys.key] = apiKey.trim();
      if (baseURL.trim()) {
        const url = new URL(baseURL.trim());
        if (
          !['http:', 'https:'].includes(url.protocol) ||
          url.username ||
          url.password
        )
          throw new Error(t('providers.invalid'));
        next.env[keys.url] = url.toString().replace(/\/+$/, '');
      }
    }
    if (next.customAcp) {
      const parsed: unknown = JSON.parse(args);
      if (
        !Array.isArray(parsed) ||
        parsed.some((value) => typeof value !== 'string')
      )
        throw new Error(t('providers.invalid'));
      next.customAcp = { ...next.customAcp, args: parsed };
    }
    if (next.agentType === 'pi') {
      const paths = extensions
        .split(/\r?\n/)
        .map((path) => path.trim())
        .filter(Boolean);
      next.runtimeOverrides = { ...next.runtimeOverrides, piExtensions: paths };
    }
    if (next.titleGeneration) {
      const values: unknown = JSON.parse(titleOptions);
      if (
        !values ||
        typeof values !== 'object' ||
        Array.isArray(values) ||
        Object.values(values).some(
          (value) => typeof value !== 'string' && typeof value !== 'boolean',
        )
      )
        throw new Error(t('providers.invalid'));
      next.titleGeneration = {
        configOptionValues: values as Record<string, string | boolean>,
      };
    }
    if (JSON.stringify(next).length > 128 * 1024)
      throw new Error(t('providers.overLimit'));
    return next;
  };
  const persist = async () => {
    const value = build();
    const serialized = JSON.stringify(value);
    if (persisted.current?.request === serialized)
      return persisted.current.config;
    const reply = await service({
      action: 'save',
      workspaceId,
      machineId: machine.id,
      config: value,
      revision: revision.current,
      queue: !revision.current && queueProvider(value, machine),
    });
    if (!reply.revision) throw new Error('invalid_provider_response');
    revision.current = reply.revision;
    const saved = reply.config ?? value;
    persisted.current = { request: serialized, config: saved };
    return saved;
  };
  const operate = async (action: 'verify' | 'install' | 'authenticate') => {
    if (saving.current) return;
    saving.current = true;
    setBusy(true);
    const tested = identity;
    try {
      const saved = await persist();
      const reply = await service({
        action,
        workspaceId,
        machineId: machine.id,
        id: saved.id,
      });
      if (!reply.operation) throw new Error('invalid_provider_response');
      const result = await present(
        ProviderOperationScreen,
        {
          workspaceId,
          machineId: machine.id,
          configId: saved.id,
          operation: reply.operation,
          service,
        },
        {
          title: t(
            action === 'authenticate'
              ? 'providers.authentication'
              : 'providers.title',
          ),
        },
      );
      if (result.status === 'completed' && result.value.state === 'completed') {
        if (action === 'verify' && result.value.capability) {
          setCapability(result.value.capability);
          if (!result.value.capability.authRequired) setVerified(tested);
        }
        if (action === 'install') setRuntime(providerStatus('installed'));
        if (action === 'authenticate') {
          setVerified('');
          setCapability(undefined);
        }
      }
      if (mounted.current) {
        const latest = await service({
          action: 'get',
          workspaceId,
          machineId: machine.id,
          id: saved.id,
        });
        if (
          latest.config &&
          JSON.stringify(latest.config) !== JSON.stringify(saved)
        )
          throw new Error('provider_conflict');
        revision.current = latest.revision;
      }
    } catch (cause) {
      showToast(providerError(cause), 'error');
    } finally {
      saving.current = false;
      if (mounted.current) setBusy(false);
    }
  };
  const save = async () => {
    if (saving.current) return;
    saving.current = true;
    setBusy(true);
    try {
      await persist();
      finish();
    } catch (cause) {
      showToast(providerError(cause, true), 'error');
    } finally {
      saving.current = false;
      if (mounted.current) setBusy(false);
    }
  };
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('providers.save'),
        accessibilityLabel: t('providers.save'),
        variant: 'prominent' as const,
        disabled: loading || busy || overLimit || !config?.name.trim(),
        onPress: () => void save(),
      },
    ],
    [
      loading,
      overLimit,
      busy,
      config,
      envText,
      apiKey,
      baseURL,
      args,
      extensions,
      titleOptions,
    ],
  );
  const left = useMemo(
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
  const header = (
    <NativeNavigationHeader
      title={t('providers.edit')}
      items={actions}
      leftItems={left}
    />
  );
  if (loading || !config)
    return (
      <Screen style={{ backgroundColor: colors.background }}>
        {header}
        <FormGroup footer={loading ? t('providers.loading') : error}>
          {!loading ? (
            <Button
              testID="provider-editor-retry"
              label={t('providers.retry')}
              onPress={() => void load()}
            />
          ) : null}
        </FormGroup>
      </Screen>
    );
  if (overLimit)
    return (
      <Screen style={{ backgroundColor: colors.background }}>
        {header}
        <FormGroup header={t('providers.name')} footer={machine.name}>
          <AppText style={styles.message}>{config.name}</AppText>
        </FormGroup>
        <FormGroup
          header={t('providers.manageOnDesktop')}
          footer={t('providers.manageOnDesktopHint', { machine: machine.name })}
        >
          <AppText testID="provider-over-limit" style={styles.message}>
            {t('providers.overLimit')}
          </AppText>
        </FormGroup>
      </Screen>
    );
  const keys = connectionKeys(config);
  const override = runtimeOverrideKey[config.agentType];
  const nativeTitles =
    config.cliType === 'builtin' &&
    ['claude', 'grok'].includes(config.agentType) &&
    !Object.values(config.runtimeOverrides ?? {}).some((value) =>
      Array.isArray(value) ? value.length > 0 : !!value?.trim(),
    );
  const hasTitles = nativeTitles || capability?.providesSessionTitle === true;
  const verifiedNow = verified === identity && !!verified;
  const update = (next: Partial<ProviderConfig>) =>
    setConfig((config) => (config ? { ...config, ...next } : config));
  const profile = config.codexAuth;
  let profileLabel = '';
  if (profile)
    profileLabel = t(
      profile.mode === 'chatgpt' ? 'providers.chatgpt' : 'providers.apiMode',
    );
  const profileHint =
    profile?.mode === 'api-key' ? t('providers.codexKeyHint') : undefined;
  const usesProtocolAuth =
    config.cliType !== 'builtin' || config.agentType === 'devin';
  let authenticationSupported = ['codex', 'claude', 'kimi', 'grok'].includes(
    config.agentType,
  );
  if (usesProtocolAuth)
    authenticationSupported =
      (machine.capabilities.acpProtocolAuthentication ?? 0) >= 2 &&
      capability?.authRequired === true;
  const installationSupported =
    config.cliType === 'registry' ||
    (config.cliType === 'builtin' &&
      ['codex', 'claude', 'kimi', 'grok', 'devin', 'pi'].includes(
        config.agentType,
      ));
  return (
    <Screen
      style={{ backgroundColor: colors.background }}
      automaticallyAdjustKeyboardInsets
    >
      {header}
      <FormGroup header={t('providers.name')} footer={machine.name}>
        <TextInput
          testID="provider-name"
          accessibilityLabel={t('providers.name')}
          style={inputStyle}
          value={config.name}
          onChangeText={(name) => update({ name })}
          maxLength={200}
          editable={!busy}
        />
      </FormGroup>
      <FormGroup header={t('providers.type')}>
        <AppText style={styles.message}>{providerTypeLabel(config)}</AppText>
        {config.cliType === 'registry' ? (
          <TextInput
            testID="provider-agent-type"
            accessibilityLabel={t('providers.agentType')}
            style={inputStyle}
            value={config.agentType}
            onChangeText={(agentType) => update({ agentType })}
            autoCorrect={false}
            autoCapitalize="none"
            editable={!busy}
          />
        ) : null}
      </FormGroup>
      {config.customAcp ? (
        <FormGroup header={t('providers.custom')}>
          <TextInput
            testID="provider-command"
            accessibilityLabel={t('providers.command')}
            style={inputStyle}
            value={config.customAcp.command}
            onChangeText={(command) =>
              update({ customAcp: { ...config.customAcp, command } })
            }
            placeholder={t('providers.command')}
            autoCorrect={false}
            autoCapitalize="none"
            editable={!busy}
          />
          <TextInput
            testID="provider-args"
            accessibilityLabel={t('providers.args')}
            style={inputStyle}
            value={args}
            onChangeText={setArgs}
            autoCorrect={false}
            autoCapitalize="none"
            editable={!busy}
          />
        </FormGroup>
      ) : null}
      {keys ? (
        <FormGroup header={t('providers.connection')}>
          <TextInput
            testID="provider-api-key"
            accessibilityLabel={t('providers.apiKey')}
            placeholder={t('providers.apiKey')}
            style={inputStyle}
            value={apiKey}
            onChangeText={setApiKey}
            secureTextEntry
            autoCorrect={false}
            autoCapitalize="none"
            editable={!busy}
          />
          <TextInput
            testID="provider-base-url"
            accessibilityLabel={t('providers.baseURL')}
            placeholder={t('providers.baseURL')}
            style={inputStyle}
            value={baseURL}
            onChangeText={setBaseURL}
            keyboardType="url"
            autoCorrect={false}
            autoCapitalize="none"
            editable={!busy}
          />
        </FormGroup>
      ) : null}
      {profile ? (
        <FormGroup header={t('providers.connection')} footer={profileHint}>
          {!item && (
            <RNView style={styles.modes}>
              <Button
                label={t('providers.chatgpt')}
                disabled={busy}
                onPress={() =>
                  update({
                    codexAuth: {
                      mode: 'chatgpt',
                      profileId: profile.profileId,
                    },
                  })
                }
              />
              <Button
                label={t('providers.apiMode')}
                disabled={busy}
                onPress={() =>
                  update({
                    codexAuth: {
                      mode: 'api-key',
                      profileId: profile.profileId,
                      baseUrl: 'https://api.openai.com/v1',
                    },
                  })
                }
              />
            </RNView>
          )}
          {!!item && <AppText style={styles.message}>{profileLabel}</AppText>}
          {profile.mode === 'api-key' && (
            <TextInput
              testID="provider-base-url"
              accessibilityLabel={t('providers.baseURL')}
              style={inputStyle}
              value={profile.baseUrl}
              onChangeText={(baseUrl) =>
                update({ codexAuth: { ...profile, baseUrl } })
              }
              autoCorrect={false}
              autoCapitalize="none"
              editable={!busy}
            />
          )}
        </FormGroup>
      ) : null}
      <FormGroup header={t('providers.env')} footer={t('providers.envHint')}>
        <TextInput
          testID="provider-env"
          accessibilityLabel={t('providers.env')}
          style={multiline}
          multiline
          scrollEnabled={false}
          value={envText}
          onChangeText={setEnvText}
          maxLength={128 * 1024}
          autoCorrect={false}
          autoCapitalize="none"
          editable={!busy}
        />
      </FormGroup>
      <FormGroup header={t('providers.prompt')}>
        <TextInput
          testID="provider-prompt"
          accessibilityLabel={t('providers.prompt')}
          style={multiline}
          multiline
          scrollEnabled={false}
          value={config.prompt ?? ''}
          onChangeText={(prompt) => update({ prompt })}
          maxLength={32000}
          editable={!busy}
        />
      </FormGroup>
      {config.cliType === 'builtin' && override && !profile ? (
        <FormGroup
          header={t('providers.override')}
          footer={t('providers.overrideHint')}
        >
          <TextInput
            testID="provider-override"
            accessibilityLabel={t('providers.override')}
            style={inputStyle}
            value={String(config.runtimeOverrides?.[override] ?? '')}
            autoCorrect={false}
            autoCapitalize="none"
            editable={!busy}
            onChangeText={(value) =>
              update({
                runtimeOverrides: {
                  ...config.runtimeOverrides,
                  [override]: value,
                },
              })
            }
          />
        </FormGroup>
      ) : null}
      {config.agentType === 'pi' &&
      (machine.capabilities.piExtensions ?? 0) >= 1 ? (
        <FormGroup
          header={t('providers.extensions')}
          footer={t('providers.extensionsHint')}
        >
          <TextInput
            testID="provider-extensions"
            accessibilityLabel={t('providers.extensions')}
            style={multiline}
            multiline
            scrollEnabled={false}
            value={extensions}
            onChangeText={setExtensions}
            autoCorrect={false}
            autoCapitalize="none"
            editable={!busy}
          />
        </FormGroup>
      ) : null}
      <FormGroup
        header={t('providers.titleGeneration')}
        footer={
          hasTitles ? t('providers.titleOwned') : t('providers.titleHint')
        }
      >
        {!hasTitles && (
          <RNView style={styles.toggle}>
            <AppText>{t('providers.titleGeneration')}</AppText>
            <Switch
              testID="provider-auto-title"
              accessibilityLabel={t('providers.titleGeneration')}
              value={!!config.titleGeneration}
              onValueChange={(enabled) =>
                update({
                  titleGeneration: enabled
                    ? { configOptionValues: {} }
                    : undefined,
                })
              }
              disabled={busy}
              trackColor={{ true: colors.accent }}
            />
          </RNView>
        )}
        {!hasTitles && config.titleGeneration ? (
          <TextInput
            testID="provider-title-options"
            accessibilityLabel={t('providers.titleOptions')}
            style={multiline}
            multiline
            scrollEnabled={false}
            value={titleOptions}
            onChangeText={setTitleOptions}
            autoCorrect={false}
            autoCapitalize="none"
            editable={!busy}
          />
        ) : null}
      </FormGroup>
      <FormGroup
        footer={
          verifiedNow ? t('providers.verified') : t('providers.unverified')
        }
      >
        <AppText testID="provider-verification-state" style={styles.message}>
          {verifiedNow ? t('providers.verified') : t('providers.unverified')}
        </AppText>
        <Button
          testID="provider-verify"
          label={t('providers.verify')}
          disabled={busy || machine.availability !== 'online'}
          onPress={() => void operate('verify')}
        />
        <Button
          testID="provider-authenticate"
          label={t('providers.signIn')}
          disabled={
            busy ||
            machine.availability !== 'online' ||
            !authenticationSupported
          }
          onPress={() => void operate('authenticate')}
        />
      </FormGroup>
      <FormGroup
        header={t('providers.status')}
        footer={t('providers.runtimeHint')}
      >
        {runtime ? (
          <AppText testID="provider-runtime-status" style={styles.message}>
            {runtime}
          </AppText>
        ) : null}
        <Button
          testID="provider-check-runtime"
          label={t('providers.status')}
          disabled={busy || machine.availability !== 'online'}
          onPress={() => {
            if (saving.current) return;
            saving.current = true;
            setBusy(true);
            void persist()
              .then((saved) =>
                service({
                  action: 'status',
                  workspaceId,
                  machineId: machine.id,
                  id: saved.id,
                }),
              )
              .then((reply) => {
                if (reply.status)
                  setRuntime(
                    [providerStatus(reply.status.status), reply.status.version]
                      .filter(Boolean)
                      .join(' · '),
                  );
              })
              .catch((cause) => showToast(providerError(cause), 'error'))
              .finally(() => {
                saving.current = false;
                if (mounted.current) setBusy(false);
              });
          }}
        />
        <Button
          testID="provider-install"
          label={t('providers.install')}
          disabled={
            busy || machine.availability !== 'online' || !installationSupported
          }
          onPress={() => void operate('install')}
        />
      </FormGroup>
      {item?.state === 'failed' ? (
        <FormGroup footer={t('providers.taskHint')}>
          <Button
            testID="provider-retry-setup"
            label={t('providers.retrySetup')}
            disabled={busy}
            onPress={() => {
              setBusy(true);
              void service({
                action: 'retry',
                workspaceId,
                machineId: machine.id,
                id: item.id,
              })
                .then(() => finish())
                .catch((cause) => showToast(providerError(cause), 'error'))
                .finally(() => {
                  if (mounted.current) setBusy(false);
                });
            }}
          />
        </FormGroup>
      ) : null}
      {item || revision.current ? (
        <FormGroup>
          <Button
            testID="provider-delete"
            label={t('providers.delete')}
            destructive
            disabled={busy}
            onPress={() =>
              Alert.alert(
                t('providers.delete'),
                t('providers.deleteMessage', { machine: machine.name }),
                [
                  { text: t('common.cancel'), style: 'cancel' },
                  {
                    text: t('common.delete'),
                    style: 'destructive',
                    onPress: () => {
                      setBusy(true);
                      void service({
                        action: 'delete',
                        workspaceId,
                        machineId: machine.id,
                        id: config.id,
                        revision: revision.current,
                      })
                        .then(() => finish())
                        .catch((cause) =>
                          showToast(providerError(cause), 'error'),
                        )
                        .finally(() => {
                          if (mounted.current) setBusy(false);
                        });
                    },
                  },
                ],
              )
            }
          />
        </FormGroup>
      ) : null}
    </Screen>
  );
}

export const ProviderEditorScreen = definePage<Params>({
  id: 'provider-editor',
  title: t('providers.edit'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from Provider management');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
const styles = StyleSheet.create({
  multiline: { minHeight: 88, textAlignVertical: 'top', paddingTop: 12 },
  message: { minHeight: 44, paddingHorizontal: 16, paddingVertical: 12 },
  modes: { paddingHorizontal: 16 },
  toggle: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    minHeight: 44,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
});
