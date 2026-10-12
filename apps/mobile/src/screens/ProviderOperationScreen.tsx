import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Linking, StyleSheet, TextInput, View as RNView } from 'react-native';
import { NativeNavigationHeader } from '@lody-ios/kit';
import type {
  ProviderOperationResult,
  ProviderService,
} from '@lody/cloud-runtime/models/providers';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import {
  authenticationContent,
  providerError,
  providerStatus,
} from '@/features/providers/provider-config';
import { usePalette } from '@/lib/theme/palette';
import { Screen } from '@/ui/Screen';
import { FormGroup, formInputStyle } from '@/ui/FormGroup';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { showToast } from '@/ui/toast';
import { t } from '@/lib/i18n';
import { ProviderChoiceScreen } from './ProviderChoiceScreen';

type Params = {
  workspaceId: string;
  machineId: string;
  configId: string;
  operation: ProviderOperationResult;
  service: ProviderService;
};

function View() {
  const { params, present, finish, cancel } = usePageRuntime<
    Params,
    ProviderOperationResult
  >();
  const { service, workspaceId, machineId, configId } = params;
  const colors = usePalette();
  const [operation, setOperation] = useState(params.operation);
  const current = useRef(operation);
  current.current = operation;
  const [values, setValues] = useState<Record<string, string>>({});
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const active = useRef(true);
  const inputStyle = [formInputStyle, { color: colors.label }];
  useEffect(() => {
    active.current = true;
    const operationId = operation.id;
    let timer: ReturnType<typeof setTimeout>;
    let stopped = false;
    const poll = async () => {
      if (
        stopped ||
        current.current.id !== operationId ||
        current.current.state !== 'running'
      )
        return;
      try {
        const result = await service({
          action: 'poll',
          workspaceId,
          machineId,
          operationId,
        });
        if (stopped || !result.operation) return;
        current.current = result.operation;
        setOperation(result.operation);
        setError('');
      } catch (cause) {
        if (!stopped) setError(providerError(cause));
      }
      if (!stopped) timer = setTimeout(() => void poll(), 700);
    };
    void poll();
    return () => {
      active.current = false;
      stopped = true;
      clearTimeout(timer);
      void service({
        action: 'cancel',
        workspaceId,
        machineId,
        operationId,
      }).catch(() => {});
    };
  }, [operation.id, service, workspaceId, machineId]);
  const retry = useCallback(async () => {
    if (busy) return;
    setBusy(true);
    try {
      const reply = await service({
        action: current.current.kind,
        workspaceId,
        machineId,
        id: configId,
      });
      if (!reply.operation) throw new Error('invalid_provider_response');
      current.current = reply.operation;
      setOperation(reply.operation);
      setValues({});
      setCode('');
      setError('');
    } catch (cause) {
      setError(providerError(cause));
    } finally {
      if (active.current) setBusy(false);
    }
  }, [service, workspaceId, machineId, configId, busy]);
  const submit = useCallback(
    async (
      input: {
        action: 'accept' | 'decline' | 'cancel';
        methodId?: string;
        content?: Record<string, string>;
      },
      authorizationCode?: string,
    ) => {
      if (busy) return false;
      setBusy(true);
      try {
        const reply = await service({
          action: 'auth-input',
          workspaceId,
          machineId,
          operationId: current.current.id,
          ...(authorizationCode !== undefined
            ? { code: authorizationCode }
            : { input }),
        });
        if (reply.operation) {
          current.current = reply.operation;
          setOperation(reply.operation);
        }
        setValues({});
        setCode('');
        setError('');
        return true;
      } catch (cause) {
        setError(providerError(cause));
        return false;
      } finally {
        if (active.current) setBusy(false);
      }
    },
    [busy, service, workspaceId, machineId],
  );
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('common.done'),
        accessibilityLabel: t('common.done'),
        disabled: busy,
        onPress: () => finish(current.current),
      },
    ],
    [busy, finish],
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
  const progress = operation.progress;
  let status = providerStatus(operation.state);
  if (operation.state === 'running')
    status = providerStatus(progress?.status ?? 'starting');
  const terminalError = operation.error
    ? providerError(new Error(operation.error))
    : '';
  const capabilityHint = operation.capability?.authRequired
    ? t('providers.awaiting-auth')
    : t('providers.verified');
  return (
    <Screen
      style={{ backgroundColor: colors.background }}
      automaticallyAdjustKeyboardInsets
    >
      <NativeNavigationHeader
        title={t(
          operation.kind === 'authenticate'
            ? 'providers.authentication'
            : 'providers.title',
        )}
        items={actions}
        leftItems={left}
      />
      <FormGroup footer={t('providers.runtimeHint')}>
        <RNView style={styles.message}>
          <AppText testID="provider-operation-state" accessibilityRole="text">
            {status}
          </AppText>
          {progress?.percent !== undefined ? (
            <AppText testID="provider-operation-progress">
              {Math.round(progress.percent)}%
            </AppText>
          ) : null}
          {progress?.version ? (
            <AppText variant="meta">{progress.version}</AppText>
          ) : null}
        </RNView>
      </FormGroup>
      {error || terminalError ? (
        <FormGroup footer={error || terminalError}>
          <Button
            testID="provider-operation-retry"
            label={t('providers.retry')}
            disabled={busy}
            onPress={() => void retry()}
          />
        </FormGroup>
      ) : null}
      {progress?.authorizationUrl && operation.state === 'running' ? (
        <FormGroup header={t('providers.authentication')}>
          {!!progress.userCode && (
            <AppText testID="provider-user-code" style={styles.message}>
              {progress.userCode}
            </AppText>
          )}
          <Button
            testID="provider-open-authorization"
            label={t('providers.openAuthorization')}
            disabled={busy}
            onPress={() => {
              const url = progress.authorizationUrl;
              if (!url) return;
              const open = () =>
                Linking.openURL(url).catch(() =>
                  showToast(t('providers.requestFailed'), 'error'),
                );
              if (progress.requiresAuthorizationConsent)
                void submit({ action: 'accept' }).then((accepted) => {
                  if (accepted) void open();
                });
              else void open();
            }}
          />
          {progress.requiresAuthorizationConsent && (
            <Button
              label={t('providers.decline')}
              disabled={busy}
              onPress={() => void submit({ action: 'decline' })}
            />
          )}
        </FormGroup>
      ) : null}
      {progress?.acceptsAuthorizationCode && operation.state === 'running' ? (
        <FormGroup header={t('providers.authorizationCode')}>
          <TextInput
            testID="provider-authorization-code"
            accessibilityLabel={t('providers.authorizationCode')}
            style={inputStyle}
            value={code}
            onChangeText={setCode}
            secureTextEntry
            autoCorrect={false}
            autoCapitalize="none"
            editable={!busy}
          />
          <Button
            testID="provider-submit-code"
            label={t('providers.submit')}
            disabled={busy || !code.trim()}
            onPress={() => void submit({ action: 'accept' }, code)}
          />
        </FormGroup>
      ) : null}
      {progress?.authMethods?.length && operation.state === 'running' ? (
        <FormGroup header={t('providers.auth-methods')}>
          {progress.authMethods.map((method) => (
            <Button
              key={method.id}
              testID={`provider-method:${method.id}`}
              label={method.name}
              disabled={busy}
              onPress={() =>
                void submit({ action: 'accept', methodId: method.id })
              }
            />
          ))}
        </FormGroup>
      ) : null}
      {progress?.form && operation.state === 'running' ? (
        <FormGroup
          header={progress.form.title ?? t('providers.authentication')}
        >
          {progress.form.fields.map((field) => {
            const value = values[field.id] ?? field.defaultValue ?? '';
            if (field.type === 'select')
              return (
                <Button
                  key={field.id}
                  label={`${field.label}: ${value}`}
                  disabled={busy}
                  onPress={() =>
                    void present(
                      ProviderChoiceScreen,
                      {
                        choices: (field.options ?? []).map((option) => ({
                          id: option.value,
                          name: option.label,
                        })),
                        selected: value,
                      },
                      { title: field.label },
                    ).then((result) => {
                      if (result.status === 'completed')
                        setValues((values) => ({
                          ...values,
                          [field.id]: result.value,
                        }));
                    })
                  }
                />
              );
            return (
              <TextInput
                key={field.id}
                testID={`provider-auth-field:${field.id}`}
                accessibilityLabel={field.label}
                placeholder={field.label}
                placeholderTextColor={colors.secondaryLabel}
                style={inputStyle}
                value={value}
                onChangeText={(value) =>
                  setValues((values) => ({ ...values, [field.id]: value }))
                }
                secureTextEntry={field.type === 'secret'}
                autoCorrect={false}
                autoCapitalize="none"
                editable={!busy}
              />
            );
          })}
          <Button
            testID="provider-submit-auth"
            label={t('providers.submit')}
            disabled={busy}
            onPress={() => {
              try {
                void submit({
                  action: 'accept',
                  content: authenticationContent(progress, values),
                });
              } catch (cause) {
                setError(providerError(cause));
              }
            }}
          />
          <Button
            label={t('providers.decline')}
            disabled={busy}
            onPress={() => void submit({ action: 'decline' })}
          />
        </FormGroup>
      ) : null}
      {operation.capability ? (
        <FormGroup header={t('providers.models')} footer={capabilityHint}>
          {operation.capability.models.map((model) => (
            <AppText
              key={model.modelId}
              testID={`provider-model:${model.modelId}`}
              style={styles.message}
            >
              {model.name}
            </AppText>
          ))}
          {!operation.capability.models.length && (
            <AppText style={styles.message}>{t('providers.noModels')}</AppText>
          )}
        </FormGroup>
      ) : null}
    </Screen>
  );
}

export const ProviderOperationScreen = definePage<
  Params,
  ProviderOperationResult
>({
  id: 'provider-operation',
  title: t('providers.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from Provider configuration');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
const styles = StyleSheet.create({
  message: { minHeight: 44, paddingHorizontal: 16, paddingVertical: 12 },
});
