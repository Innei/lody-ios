import type { Project } from '../../models/catalog.ts';
import type {
  CreatePrefs,
  CreationOptions,
  ModelChoice,
  ProjectPrefs,
} from '../../models/send.ts';
// Relative on purpose: this module is imported directly by node --test.
import { capabilityFor } from '../../cloud/send/capability.ts';

export type {
  CreatePrefs,
  ModelChoice,
  ProjectPrefs,
} from '../../models/send.ts';

export const createPrefsKey = (userId: string, workspaceId: string) =>
  `create:${userId}:${workspaceId}`;

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
  const effort =
    modelId &&
    saved.effort &&
    capability?.reasoningEfforts[modelId]?.includes(saved.effort)
      ? saved.effort
      : undefined;
  const modeId = capability?.modes.some((m) => m.id === saved.modeId)
    ? saved.modeId
    : undefined;
  return {
    machineId: agent?.machineId ?? '',
    agentKey: agent ? `${agent.machineId}:${agent.id}` : '',
    choice: { modelId, effort, modeId } satisfies ModelChoice,
  };
}

export function withSelection(
  prefs: CreatePrefs | null | undefined,
  projectId: string,
  selection: ProjectPrefs,
): CreatePrefs {
  return {
    projectId,
    projects: { ...prefs?.projects, [projectId]: selection },
  };
}
