import { useCallback, useRef, useState } from 'react';
import { View as RNView } from 'react-native';
import { NativeChat, NativeNavigationHeader, uuid } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useComposerRunOptions } from '@/hooks/screens/useComposerRunOptions';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import {
  detachChangedRole,
  selectedRoleChoice,
} from '@/features/sessions/runOptions';
import {
  runOptionsFailureNotice,
  runOptionsRecoveryAction,
} from '@/features/sessions/runOptionsRecovery';
import { t } from '@/lib/i18n';
import { createPrefsKey } from '@/features/sessions/createPrefs';
import { writeLocal } from '@/cloud/kv';
import { getPendingSendStore } from '@/cloud/send/pendingSends';
import { withPermissionMode } from '@/cloud/send/capability';
import { CreateSessionScreen } from '../CreateSessionScreen';
import { AgentRolesScreen } from '../AgentRolesScreen';
import type { RunOptionsCatalog } from '@lody/cloud-runtime/models/run-options';
import type { Capability, ModelChoice } from '@lody/cloud-runtime/models/send';

export const runOptionsFixture: RunOptionsCatalog = {
  roles: [
    {
      id: 'reviewer',
      name: 'Reviewer',
      agentName: 'Fixture Agent',
      machineId: 'ui',
      agentConfigId: 'agent',
      cliType: 'builtin',
      agentType: 'codex',
      revision: 3,
      available: true,
      runConfig: { modelId: 'a', modeId: 'read-only' },
    },
    {
      id: 'missing',
      name: 'Unavailable Role',
      agentName: '',
      machineId: 'ui',
      agentConfigId: 'missing',
      revision: 1,
      available: false,
      unavailableReason: 'agent_config_missing',
      runConfig: {},
    },
    {
      id: 'unsupported',
      name: 'Unsupported Role',
      agentName: 'Fixture Agent',
      machineId: 'ui',
      agentConfigId: 'agent',
      revision: 1,
      available: false,
      unavailableReason: 'run_config_unsupported',
      runConfig: { configOptionValues: { preset: '' } },
    },
  ],
  mcpServers: [
    {
      id: 'docs',
      name: 'Documentation',
      transport: 'stdio',
      enabledByDefault: true,
    },
    {
      id: 'browser',
      name: 'Browser',
      transport: 'http',
      enabledByDefault: false,
    },
  ],
  worktreeAvailable: true,
};

const capability: Capability = {
  machineId: 'ui',
  cliType: 'builtin',
  agentType: 'codex',
  models: [
    { id: 'a', name: 'Model A' },
    { id: 'b', name: 'Model B' },
  ],
  modes: [
    { id: 'read-only', name: 'Read Only' },
    { id: 'agent-full-access', name: 'Full Access' },
  ],
  reasoningEfforts: {},
  steer: false,
};
const workspaceId = 'ui-run-options';
const userId = 'ui-run-options';
const project = {
  id: 'ui:local:run-options',
  name: 'Run Options',
  machineId: 'ui',
  rootPath: '/fixture',
};

function View() {
  const { present } = usePageRuntime();
  const [choice, setChoice] = useState<ModelChoice>({
    modelId: 'b',
    modeId: 'agent-full-access',
    mcpServerIds: ['docs'],
  });
  const [result, setResult] = useState('ready');
  const [clear, setClear] = useState(0);
  const failLookup = useRef(false);
  const loadRunOptions = useCallback(async () => {
    if (failLookup.current) {
      failLookup.current = false;
      throw new Error('Fixture workspace stream unavailable');
    }
    return JSON.stringify(runOptionsFixture);
  }, []);
  const runOptions = useComposerRunOptions(
    { workspaceId, userId, machineId: 'ui', agentConfigId: 'agent' },
    undefined,
    loadRunOptions,
  );
  const recovery = runOptionsRecoveryAction(runOptions);
  const ready =
    !runOptions.loading &&
    !runOptions.error &&
    runOptions.catalog.roles.length > 0;
  const permissions = capability.modes.map((mode) => ({
    id: mode.id,
    title: mode.name,
  }));

  async function openCreate(unavailable = false) {
    await writeLocal(createPrefsKey(userId, workspaceId), null);
    const attempted = new Set<string>();
    const result = await present(CreateSessionScreen, {
      workspaceId,
      fixtureUserId: userId,
      projects: [project],
      initialText: 'Review changes',
      loadOptions: async (projectId) => {
        const key = projectId ?? 'chat';
        let runOptions = runOptionsFixture;
        if (unavailable && !attempted.has(key)) {
          attempted.add(key);
          runOptions = { roles: [], mcpServers: [], unavailable: true };
        }
        return {
          sessionId: uuid.v4(),
          project: projectId ? project : undefined,
          agents: [
            {
              id: 'agent',
              name: 'Fixture Agent',
              machineId: 'ui',
              machineName: 'Fixture Mac',
              cliType: 'builtin',
              agentType: 'codex',
            },
            {
              id: 'legacy',
              name: 'Legacy Claude',
              machineId: 'ui',
              machineName: 'Fixture Mac',
              cliType: 'builtin',
              agentType: 'claude',
            },
          ],
          capabilities: [
            capability,
            {
              machineId: 'ui',
              cliType: 'builtin',
              agentType: 'claude',
              models: [{ id: 'opus', name: 'Claude Opus' }],
              modes: [{ id: 'plan', name: 'Plan' }],
              reasoningEfforts: { opus: ['low', 'high'] },
              steer: false,
            },
          ],
          runOptions,
        };
      },
    });
    if (result.status === 'completed') {
      const record = getPendingSendStore(userId, workspaceId)
        .getSnapshot()
        .records.find(
          (record) => record.session.id === result.value.session.id,
        );
      setResult(
        JSON.stringify({
          choice: record?.send.choice,
          creation: record?.send.creation
            ? JSON.parse(record.send.creation)
            : undefined,
        }),
      );
    }
  }

  return (
    <RNView style={{ flex: 1 }}>
      <NativeNavigationHeader
        items={[
          {
            type: 'menu',
            icon: { type: 'sfSymbol', name: 'ellipsis' },
            accessibilityLabel: t('common.more'),
            menu: {
              items: [
                {
                  type: 'action',
                  title: 'Fail run options lookup',
                  onPress: () => {
                    failLookup.current = true;
                    runOptions.refresh();
                  },
                },
                {
                  type: 'action',
                  title: 'New session options unavailable',
                  onPress: () => void openCreate(true),
                },
                ...(recovery ? [recovery] : []),
              ],
            },
          },
        ]}
      />
      <RNView style={{ paddingHorizontal: 20, paddingTop: 110 }}>
        <AppText testID={ready ? 'run-options-ready' : 'run-options-status'}>
          Run options
        </AppText>
        <AppText testID="run-options-choice" variant="meta">
          {JSON.stringify(choice)}
        </AppText>
        <AppText testID="run-options-result" variant="meta">
          {result}
        </AppText>
        <Button
          testID="run-options-open-create"
          onPress={() => void openCreate()}
        >
          New session options
        </Button>
        <Button
          testID="run-options-open-roles"
          onPress={() =>
            void present(AgentRolesScreen, { fixture: runOptionsFixture })
          }
        >
          Workspace Roles
        </Button>
      </RNView>
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON="[]"
        emptyText="Choose options for this turn"
        clearDraftToken={clear}
        composerJSON={JSON.stringify({
          editable: true,
          canSend: true,
          running: false,
          sending: false,
          reconnect: false,
          placeholder: 'Review changes',
          notice: runOptionsFailureNotice(runOptions.error),
        })}
        composerOptionsJSON={JSON.stringify({
          modelId: choice.modelId ?? '',
          effort: '',
          models: capability.models.map((model) => ({
            id: model.id,
            title: model.name,
          })),
          efforts: [],
          permissionId: choice.modeId ?? '',
          permissions,
          runOptions: runOptions.catalog,
          agentRoleId: choice.agentRoleId,
          mcpServerIds: choice.mcpServerIds,
        })}
        onComposerOptionChange={({ nativeEvent }) =>
          setChoice((previous) => {
            if ('agentRoleId' in nativeEvent)
              return selectedRoleChoice(
                previous,
                runOptions.catalog.roles.find(
                  (role) => role.id === nativeEvent.agentRoleId,
                ) ?? null,
                capability,
              );
            if (nativeEvent.mcpServerIds)
              return { ...previous, mcpServerIds: nativeEvent.mcpServerIds };
            if (nativeEvent.permissionId !== undefined)
              return detachChangedRole(
                withPermissionMode(
                  capability,
                  previous,
                  nativeEvent.permissionId,
                ),
                capability,
                previous,
              );
            return detachChangedRole(
              { ...previous, modelId: nativeEvent.modelId || undefined },
              capability,
              previous,
            );
          })
        }
        onSend={({ nativeEvent }) => {
          setResult(JSON.stringify({ text: nativeEvent.text, choice }));
          setClear((value) => value + 1);
        }}
        onActivityPress={() => {}}
        onReconnect={() => {}}
      />
    </RNView>
  );
}

export const RunOptionsPreviewScreen = definePage({
  id: 'run-options-preview',
  title: 'Run options',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
