import { writeLocal } from '@/cloud/kv';
import { createPrefsKey } from '@/features/sessions/createPrefs';
import { present } from '@/lib/presentation';
import type { Project } from '@/models/catalog';
import type { CreationOptions } from '@/models/send';
import { CreateSessionScreen } from '../CreateSessionScreen';

const select = (id: string, name: string, values: string[], category = id) => ({
  id,
  name,
  category,
  type: 'select' as const,
  currentValue: values[0],
  options: values.map((id) => ({ id, name: id })),
});

function fixtureOptions(sessionId: string, project?: Project): CreationOptions {
  return {
    sessionId,
    project,
    agents: [
      {
        id: 'agent',
        name: 'Fixture Agent',
        machineId: 'ui',
        machineName: 'Fixture Mac',
        cliType: 'builtin',
        agentType: 'codex',
      },
      ...['grok', 'claude', 'deepseek'].map((agentType) => ({
        id: agentType,
        name: agentType,
        machineId: 'ui',
        machineName: 'Fixture Mac',
        cliType: 'builtin',
        agentType,
      })),
    ],
    capabilities: [
      {
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
        reasoningEfforts: { a: ['low', 'high'], b: ['low', 'high'] },
        configOptions: [
          {
            id: 'fast-mode',
            name: 'Fast mode',
            category: 'model_config',
            type: 'boolean',
            currentValue: false,
            options: [],
          },
          select('collaboration_mode', 'Collaboration mode', [
            'default',
            'plan',
          ]),
        ],
        steer: true,
      },
      {
        machineId: 'ui',
        cliType: 'builtin',
        agentType: 'grok',
        models: [
          { id: 'grok-a', name: 'Grok A' },
          { id: 'grok-b', name: 'Grok B' },
        ],
        modes: [
          { id: 'agent', name: 'Agent' },
          { id: 'plan', name: 'Plan' },
        ],
        reasoningEfforts: {
          'grok-a': ['low', 'high'],
          'grok-b': ['low', 'high'],
        },
        configOptions: [
          select(
            'interaction_mode',
            'Interaction Mode',
            ['agent', 'plan'],
            'mode',
          ),
          select(
            'permission_mode',
            'Permission Mode',
            ['ask', 'auto', 'always-approve'],
            '_permission',
          ),
        ],
        steer: false,
      },
      {
        machineId: 'ui',
        cliType: 'builtin',
        agentType: 'claude',
        models: [{ id: 'claude', name: 'Claude' }],
        modes: [],
        reasoningEfforts: {},
        configOptions: [
          select('model', 'Model', ['claude'], 'model'),
          select('effort', 'Effort', ['low', 'high'], 'thought_level'),
          {
            id: 'fast',
            name: 'Fast mode',
            category: 'model_config',
            type: 'boolean',
            currentValue: false,
            options: [],
          },
        ],
        steer: false,
      },
      {
        machineId: 'ui',
        cliType: 'builtin',
        agentType: 'deepseek',
        models: [],
        modes: [],
        reasoningEfforts: {},
        configOptions: [
          select('agent_preset', 'Agent preset', ['standard', 'coder']),
        ],
        steer: false,
      },
    ],
  };
}

export async function openModelMemory() {
  const workspaceId = 'ui-model-memory';
  await writeLocal(createPrefsKey('', workspaceId), null);
  const project = {
    id: 'ui:local:models',
    name: 'Model Memory',
    machineId: 'ui',
    rootPath: '/fixture',
  };
  await present(CreateSessionScreen, {
    workspaceId,
    projects: [project],
    projectId: project.id,
    loadOptions: async () => fixtureOptions('ui-model-memory', project),
  });
}

export async function openCreateParity() {
  const workspaceId = 'ui-project-picker';
  await writeLocal(createPrefsKey('', workspaceId), null);
  const projects: Project[] = [
    {
      id: 'ui:local:alpha',
      name: 'Alpha',
      machineId: 'ui',
      rootPath: '/tmp/alpha',
    },
    {
      id: 'ui:local:beta',
      name: 'Beta',
      machineId: 'ui',
      rootPath: '/tmp/beta',
    },
  ];
  await present(CreateSessionScreen, {
    workspaceId,
    projects,
    loadOptions: async (projectId) =>
      fixtureOptions(
        'ui-create-parity',
        projects.find((project) => project.id === projectId),
      ),
  });
}
