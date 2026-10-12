import type {
  ProviderConfig,
  ProviderOperationResult,
  ProviderProgress,
  ProviderReply,
  ProviderService,
  ProviderSummary,
} from '@lody/cloud-runtime/models/providers';

/** Offline Debug service; product hosts always use requestProvider. */
export function createProviderFixture(): ProviderService {
  const configs = new Map<string, ProviderConfig>([
    [
      'claude',
      {
        id: 'claude',
        machineId: 'm1',
        name: 'Claude Code',
        cliType: 'builtin',
        agentType: 'claude',
        env: {},
        prompt: 'Keep changes focused.',
      },
    ],
    [
      'codex',
      {
        id: 'codex',
        machineId: 'm1',
        name: 'Codex',
        cliType: 'builtin',
        agentType: 'codex',
        env: {},
        prompt: '',
      },
    ],
    [
      'large-desktop',
      {
        id: 'large-desktop',
        machineId: 'm1',
        name: 'Large desktop configuration',
        cliType: 'builtin',
        agentType: 'claude',
        env: { EXTRA: 'fixture-only' },
        prompt: 'A'.repeat(32001),
      },
    ],
    [
      'pi-task',
      {
        id: 'pi-task',
        machineId: 'm1',
        name: 'Pi installation',
        cliType: 'builtin',
        agentType: 'pi',
        env: {},
        prompt: '',
      },
    ],
  ]);
  const states = new Map<string, ProviderSummary['state']>([
    ['pi-task', 'failed'],
  ]);
  const revisions = new Map<string, number>(
    [...configs.keys()].map((id) => [id, 1]),
  );
  const operations = new Map<
    string,
    { value: ProviderOperationResult; tick: number; input: boolean }
  >();
  let sequence = 0,
    firstSave = true,
    firstInstall = true;
  const copy = <T>(value: T): T => JSON.parse(JSON.stringify(value));
  return async (request): Promise<ProviderReply> => {
    if (request.action === 'list')
      return {
        machines: [
          {
            id: 'm1',
            name: 'Studio Mac',
            readOnly: false,
            availability: 'online',
            capabilities: {
              providerSetup: 1,
              codexAuthProfiles: 1,
              acpProtocolAuthentication: 2,
              acpAuthenticationInteractions: 2,
              piExtensions: 1,
            },
          },
          {
            id: 'm2',
            name: 'Shared Mac',
            readOnly: true,
            availability: 'offline',
            capabilities: {},
          },
        ],
        providers: [...configs.values()].map((config) => ({
          id: config.id,
          machineId: config.machineId,
          name: config.name,
          cliType: config.cliType,
          agentType: config.agentType,
          state: states.get(config.id) ?? 'configured',
          ...(config.id === 'large-desktop' ? { overLimit: true } : {}),
          ...(states.get(config.id) === 'failed'
            ? { failureCode: 'runtime-install-failed' as const }
            : {}),
        })),
      };
    if (request.machineId !== 'm1') throw new Error('provider_read_only');
    if (request.action === 'draft') {
      const id = `00000000-0000-4000-8000-${String(++sequence).padStart(12, '0')}`;
      const config: ProviderConfig = {
        id,
        machineId: 'm1',
        name: request.agentType,
        cliType: request.cliType,
        agentType: request.agentType,
        env: {},
        prompt: '',
      };
      if (request.cliType === 'custom') {
        config.agentType = `custom-${id}`;
        config.customAcp = { command: '' };
        config.name = 'Custom ACP';
      }
      return { config };
    }
    if (request.action === 'save') {
      if (request.config.id === 'large-desktop')
        throw new Error('provider_over_limit');
      if (firstSave) {
        firstSave = false;
        throw new Error('provider_request_failed');
      }
      if (
        configs.has(request.config.id) &&
        request.revision !== String(revisions.get(request.config.id))
      )
        throw new Error('provider_conflict');
      const saved = copy(request.config);
      saved.name = saved.name.trim();
      if (saved.customAcp)
        saved.customAcp.command = saved.customAcp.command.trim();
      configs.set(request.config.id, saved);
      const revision = (revisions.get(request.config.id) ?? 0) + 1;
      revisions.set(request.config.id, revision);
      if (request.queue) states.set(request.config.id, 'queued');
      return { config: copy(saved), revision: String(revision) };
    }
    if (
      request.action === 'poll' ||
      request.action === 'cancel' ||
      request.action === 'auth-input'
    ) {
      const operation = operations.get(request.operationId);
      if (!operation) throw new Error('provider_operation_expired');
      if (request.action === 'cancel') {
        operation.value.state = 'cancelled';
        return { operation: copy(operation.value) };
      }
      if (request.action === 'auth-input') {
        if (
          request.code === 'fixture-code' ||
          request.input?.content?.apiKey === 'fixture-key'
        )
          operation.input = true;
        else throw new Error('provider_auth_input_failed');
        operation.value.progress = { status: 'starting' };
        return { operation: copy(operation.value) };
      }
      operation.tick++;
      if (operation.value.kind === 'verify') {
        operation.value.state = 'completed';
        operation.value.capability = {
          authRequired: false,
          models: [{ modelId: 'fixture-model', name: 'Fixture Model' }],
          configOptions: [],
          providesSessionTitle: false,
        };
      } else if (operation.value.kind === 'install') {
        const steps = ['downloading', 'verifying', 'extracting', 'installed'];
        const progress: ProviderProgress = {
          status: steps[Math.min(operation.tick - 1, 3)],
          percent: Math.min(operation.tick * 25, 100),
        };
        operation.value.progress = progress;
        if (operation.tick === 4) {
          operation.value.state = firstInstall ? 'failed' : 'completed';
          if (firstInstall) operation.value.error = 'provider_request_failed';
          firstInstall = false;
        }
      } else if (operation.input) {
        operation.value.state = 'completed';
        operation.value.progress = { status: 'authenticated' };
      } else
        operation.value.progress = {
          status: 'input-required',
          interactionId: 'fixture-interaction',
          form: {
            title: 'Provider API Key',
            fields: [
              {
                id: 'apiKey',
                type: 'secret',
                label: 'API Key',
                required: true,
              },
            ],
          },
        };
      return { operation: copy(operation.value) };
    }
    if (!('id' in request)) throw new Error('invalid_provider');
    const config = configs.get(request.id);
    if (!config) throw new Error('provider_not_found');
    if (request.action === 'get')
      return {
        config: copy(config),
        revision: String(revisions.get(config.id)),
        ...(config.id === 'large-desktop' ? { overLimit: true } : {}),
      };
    if (config.id === 'large-desktop') throw new Error('provider_over_limit');
    if (request.action === 'delete') {
      configs.delete(request.id);
      states.delete(request.id);
      revisions.delete(request.id);
      return {};
    }
    if (request.action === 'retry') {
      states.set(request.id, 'queued');
      return {};
    }
    if (request.action === 'status')
      return { status: { status: 'not-installed' } };
    const id = `fixture-operation-${++sequence}`;
    const operation: ProviderOperationResult = {
      id,
      kind: request.action,
      state: 'running',
      progress: { status: 'starting' },
    };
    operations.set(id, { value: operation, tick: 0, input: false });
    return { operation: copy(operation) };
  };
}
