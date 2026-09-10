import type { Project } from '../../models/catalog.ts';
import type {
  Capability,
  CreatePrefs,
  CreationOptions,
  ModelChoice,
  ProjectPrefs,
} from '../../models/send.ts';
// Relative on purpose: this module is imported directly by node --test.
import {
  capabilityFor,
  effortsFor,
  extraConfigOptions,
  validConfigValue,
} from '../../cloud/send/capability.ts';

export type {
  CreatePrefs,
  ModelChoice,
  ProjectPrefs,
} from '../../models/send.ts';

export const createPrefsKey = (userId: string, workspaceId: string) =>
  `create:${userId}:${workspaceId}`;
export const CHAT_PREFS_KEY = 'chat';

export function rememberedContext(
  prefs: CreatePrefs | null | undefined,
): 'project' | 'chat' {
  return prefs?.context === 'chat' ? 'chat' : 'project';
}

export function rememberedProject(
  prefs: CreatePrefs | null | undefined,
  projects: Project[],
) {
  return projects.find((p) => p.id === prefs?.projectId)?.id;
}

export function restoreSelection(
  prefs: CreatePrefs | null | undefined,
  projectId: string,
  options: CreationOptions,
) {
  const saved = prefs?.projects?.[projectId] ?? {};
  const agent =
    options.agents.find((a) => `${a.machineId}:${a.id}` === saved.agentKey) ??
    options.agents.find((a) => a.machineId === saved.machineId) ??
    options.agents[0];
  const capability = capabilityFor(options, agent);
  const modelId = capability?.models.some((m) => m.id === saved.modelId)
    ? saved.modelId
    : undefined;
  return {
    machineId: agent?.machineId ?? '',
    agentKey: agent ? `${agent.machineId}:${agent.id}` : '',
    choice: rememberedModelChoice(
      prefs,
      agent ? `${agent.machineId}:${agent.id}` : '',
      capability,
      modelId,
      saved,
    ),
  };
}

const modelKey = (agentKey: string, modelId?: string) =>
  JSON.stringify([agentKey, modelId ?? null]);

export function rememberedModelChoice(
  prefs: CreatePrefs | null | undefined,
  agentKey: string,
  capability: Capability | undefined,
  modelId?: string,
  legacy?: ProjectPrefs,
): ModelChoice {
  const remembered = prefs?.modelChoices?.[modelKey(agentKey, modelId)];
  const saved =
    remembered ??
    (legacy?.agentKey === agentKey && legacy.modelId === modelId
      ? legacy
      : undefined);
  const effort =
    saved?.effort && effortsFor(capability, modelId).includes(saved.effort)
      ? saved.effort
      : undefined;
  let modeId = saved?.modeId;
  if (
    (!remembered && !modeId) ||
    (modeId && !capability?.modes.some((mode) => mode.id === modeId))
  ) {
    modeId = capability?.modes.find((mode) =>
      [
        'agent-full-access',
        'danger-full-access',
        'bypassPermissions',
        'yolo',
        'always-approve',
      ].includes(mode.id),
    )?.id;
  }
  const configOptionValues = Object.fromEntries(
    extraConfigOptions(capability).flatMap((option) => {
      const value = saved?.configOptionValues?.[option.id];
      return validConfigValue(option, value)
        ? [[option.id, value as string | boolean]]
        : [];
    }),
  );
  return {
    modelId,
    effort,
    modeId,
    ...(Object.keys(configOptionValues).length ? { configOptionValues } : {}),
  };
}

export function withSelection(
  prefs: CreatePrefs | null | undefined,
  projectId: string,
  selection: ProjectPrefs,
  context: 'project' | 'chat' = 'project',
): CreatePrefs {
  return {
    ...prefs,
    ...(context === 'chat'
      ? { context: 'chat' as const }
      : { context: 'project' as const, projectId }),
    modelChoices: {
      ...prefs?.modelChoices,
      [modelKey(selection.agentKey ?? '', selection.modelId)]: {
        modelId: selection.modelId,
        effort: selection.effort,
        modeId: selection.modeId,
        configOptionValues: selection.configOptionValues,
      },
    },
    projects: { ...prefs?.projects, [projectId]: selection },
  };
}
