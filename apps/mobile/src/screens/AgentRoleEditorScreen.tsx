import { useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Switch, TextInput, View as RNView } from 'react-native';
import { NativeGroupedList, createSendId } from '@lody-ios/kit';
import type {
  AgentRoleItem,
  RoleAgent,
} from '@lody/cloud-runtime/models/agent-roles';
import { roleError, type AgentRoleService } from '@/cloud/agent-roles';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import {
  roleEditable,
  roleReadOnlyHint,
} from '@/features/settings/agent-roles';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
import { Screen } from '@/ui/Screen';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { FormGroup, formInputStyle } from '@/ui/FormGroup';

function useActorScope(expected: string) {
  const { account } = useAuth();
  const { selected } = useCatalog();
  const { cancel } = usePageRuntime();
  const valid = expected === `${account?.user.id ?? ''}:${selected?.id ?? ''}`;
  useEffect(() => {
    if (!valid) cancel();
  }, [valid, cancel]);
  return valid;
}
function TargetPicker() {
  const { params, finish } = usePageRuntime<
    { agents: RoleAgent[]; actorScope: string },
    RoleAgent
  >();
  const valid = useActorScope(params.actorScope);
  const colors = usePalette();
  if (!valid) return null;
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={[
        {
          id: 'agents',
          rows: params.agents.map((agent, index) => ({
            id: String(index),
            title: agent.name,
            subtitle: agent.machineName,
            action: true,
          })),
        },
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        const agent = params.agents[Number(id)];
        if (agent) finish(agent);
      }}
    />
  );
}
const TargetScreen = definePage<
  { agents: RoleAgent[]; actorScope: string },
  RoleAgent
>({
  id: 'role-target',
  title: t('settings.roles.target'),
  Component: TargetPicker,
  parseRouteParams: () => {
    throw new Error('Open from role editor');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
type Params = {
  workspaceId: string;
  userId: string;
  item: AgentRoleItem | null;
  agents: RoleAgent[];
  service: AgentRoleService;
  actorScope: string;
};
function View() {
  const { params, finish, cancel, push } = usePageRuntime<Params>();
  const { item, agents, service, workspaceId, userId } = params;
  const scopeValid = useActorScope(params.actorScope);
  const colors = usePalette();
  const [name, setName] = useState(item?.name ?? ''),
    [description, setDescription] = useState(item?.description ?? ''),
    [promptPrefix, setPrompt] = useState(item?.promptPrefix ?? '');
  const [shared, setShared] = useState(item?.visibility === 'workspace');
  const [target, setTarget] = useState<RoleAgent | undefined>(agents[0]);
  const [busy, setBusy] = useState(false),
    [failure, setFailure] = useState(''),
    [deleteFailure, setDeleteFailure] = useState(false),
    [uncertain, setUncertain] = useState(false);
  const guard = useRef(false),
    id = useRef(item?.id ?? createSendId());
  const readonly = !!item && !roleEditable(item, userId);
  const editable = !readonly && !busy && !uncertain && scopeValid;
  const valid = !!name.trim() && (!!item || !!target);
  const mutate = async (remove = false) => {
    if (guard.current || readonly || uncertain || !valid || !scopeValid) return;
    guard.current = true;
    setBusy(true);
    setFailure('');
    try {
      if (remove && item)
        await service({ workspaceId, action: 'delete', base: item });
      else
        await service({
          workspaceId,
          action: 'save',
          id: id.current,
          base: item,
          fields: {
            name,
            description,
            promptPrefix,
            visibility: shared ? 'workspace' : 'private',
          },
          target: target
            ? { machineId: target.machineId, agentConfigId: target.id }
            : undefined,
        });
      finish();
    } catch (cause) {
      const error = roleError(cause);
      setDeleteFailure(remove);
      setFailure(error.message);
      setUncertain(error.uncertain);
    } finally {
      guard.current = false;
      setBusy(false);
    }
  };
  // The native header publishes separately from the form's latest render.
  const mutation = useRef(mutate);
  mutation.current = mutate;
  const actions = useMemo(
    () =>
      readonly
        ? []
        : [
            {
              type: 'button' as const,
              icon: { type: 'sfSymbol' as const, name: 'checkmark' },
              accessibilityLabel: t('common.save'),
              variant: 'prominent' as const,
              disabled: !editable || !valid,
              onPress: () => void mutation.current(),
            },
          ],
    [readonly, editable, valid],
  );
  const left = useMemo(
    () => [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'xmark' },
        accessibilityLabel: t('common.cancel'),
        disabled: busy,
        onPress: cancel,
      },
    ],
    [busy, cancel],
  );
  useSheetHeader(actions, left);
  const style = [formInputStyle, { color: colors.label }];
  const targetLabel = target
    ? `${target.machineName} · ${target.name}`
    : t('settings.roles.target');
  const error = failure ? (
    <AppText
      testID="role-error"
      accessibilityRole="alert"
      style={{ color: colors.danger, marginHorizontal: 16 }}
    >
      {failure}
    </AppText>
  ) : null;
  if (!scopeValid) return null;
  return (
    <Screen
      automaticallyAdjustKeyboardInsets
      style={{ backgroundColor: colors.background }}
    >
      <FormGroup
        header={t('settings.remote.name')}
        footer={item ? roleReadOnlyHint(item, userId) : undefined}
      >
        <TextInput
          testID="role-name"
          accessibilityLabel={t('settings.remote.name')}
          style={style}
          value={name}
          onChangeText={setName}
          editable={editable}
          maxLength={60}
          autoCorrect={false}
          clearButtonMode="while-editing"
        />
      </FormGroup>
      {deleteFailure ? null : error}
      <FormGroup header={t('settings.roles.description')}>
        <TextInput
          testID="role-description"
          accessibilityLabel={t('settings.roles.description')}
          style={style}
          value={description}
          onChangeText={setDescription}
          editable={editable}
          maxLength={140}
        />
      </FormGroup>
      <FormGroup
        header={t('settings.roles.target')}
        footer={t('settings.roles.configurationHint')}
      >
        {item ? (
          <AppText testID="role-targets" style={{ padding: 16 }}>
            {item.targets
              .map((target) => `${target.machineName} · ${target.agentName}`)
              .join('\n')}
          </AppText>
        ) : (
          <Button
            testID="role-target"
            label={targetLabel}
            disabled={!editable}
            onPress={async () => {
              const result = await push(TargetScreen, {
                agents,
                actorScope: params.actorScope,
              });
              if (result.status === 'completed') setTarget(result.value);
            }}
          />
        )}
      </FormGroup>
      <FormGroup footer={t('settings.roles.visibilityHint')}>
        <RNView
          style={{
            flexDirection: 'row',
            alignItems: 'center',
            minHeight: 44,
            padding: 16,
            gap: 12,
          }}
        >
          <AppText style={{ flex: 1 }}>{t('settings.roles.workspace')}</AppText>
          <Switch
            testID="role-shared"
            accessibilityLabel={t('settings.roles.workspace')}
            value={shared}
            onValueChange={setShared}
            disabled={!editable}
            trackColor={{ true: colors.accent }}
          />
        </RNView>
      </FormGroup>
      <FormGroup
        header={t('settings.roles.prompt')}
        footer={t('settings.roles.effectHint')}
      >
        <TextInput
          testID="role-prompt"
          accessibilityLabel={t('settings.roles.prompt')}
          style={[...style, { minHeight: 120, textAlignVertical: 'top' }]}
          value={promptPrefix}
          onChangeText={setPrompt}
          editable={editable}
          maxLength={32000}
          multiline
          scrollEnabled={false}
        />
      </FormGroup>
      {deleteFailure ? error : null}
      {item && !readonly ? (
        <FormGroup>
          <Button
            testID="role-delete"
            label={t('settings.roles.delete')}
            destructive
            disabled={!editable}
            onPress={() =>
              Alert.alert(
                t('settings.roles.delete'),
                t('settings.roles.deleteHint', { name: item.name }),
                [
                  { text: t('common.cancel'), style: 'cancel' },
                  {
                    text: t('common.delete'),
                    style: 'destructive',
                    onPress: () => void mutate(true),
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
export const AgentRoleEditorScreen = definePage<Params>({
  id: 'agent-role-editor',
  title: t('settings.roles.edit'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from Agent Roles');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
