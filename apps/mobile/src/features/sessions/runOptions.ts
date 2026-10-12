import type {
  AgentRoleOption,
  RunOptionsCatalog,
} from '@lody/cloud-runtime/models/run-options';
import type { Capability, ModelChoice } from '@lody/cloud-runtime/models/send';
import { supportsRunConfigOptions } from '@lody/cloud-runtime/protocol/run-options';

export function runOptionsForChoice(
  catalog: RunOptionsCatalog,
  choice: ModelChoice,
): RunOptionsCatalog {
  return {
    ...catalog,
    roles: catalog.roles.map((role) => {
      if (!role.available) return role;
      if (
        supportsRunConfigOptions(role.runConfig.configOptionValues, 64) &&
        supportsRunConfigOptions({
          ...choice.configOptionValues,
          ...role.runConfig.configOptionValues,
        })
      )
        return role;
      return {
        ...role,
        available: false,
        unavailableReason: 'run_config_unsupported',
      };
    }),
  };
}

export function selectedRoleChoice(
  choice: ModelChoice,
  role: AgentRoleOption | null,
  capability?: Capability,
): ModelChoice {
  if (!role) {
    const next = { ...choice, agentRoleId: null };
    delete next.agentRoleRevision;
    delete next.frozenRole;
    return next;
  }
  if (!role.available) return choice;
  if (
    !supportsRunConfigOptions(role.runConfig.configOptionValues, 64) ||
    !supportsRunConfigOptions({
      ...choice.configOptionValues,
      ...role.runConfig.configOptionValues,
    })
  )
    return choice;
  const config = role.runConfig;
  const effortId = capability?.reasoningEffortConfigId ?? 'reasoning_effort';
  const effort = config.configOptionValues?.[effortId];
  return {
    ...choice,
    ...(config.modelId ? { modelId: config.modelId } : {}),
    ...(config.modeId ? { modeId: config.modeId } : {}),
    ...(typeof effort === 'string' ? { effort } : {}),
    configOptionValues: {
      ...choice.configOptionValues,
      ...config.configOptionValues,
    },
    agentRoleId: role.id,
    agentRoleRevision: role.revision,
    frozenRole: config,
  };
}

export function detachChangedRole(
  choice: ModelChoice,
  capability?: Capability,
  previous?: ModelChoice,
): ModelChoice {
  const config = choice.frozenRole;
  if (!choice.agentRoleId) return choice;
  if (!config) {
    const changed =
      !previous ||
      ['modelId', 'effort', 'modeId'].some(
        (key) =>
          choice[key as keyof ModelChoice] !==
          previous[key as keyof ModelChoice],
      ) ||
      JSON.stringify(choice.configOptionValues ?? {}) !==
        JSON.stringify(previous.configOptionValues ?? {});
    return changed ? selectedRoleChoice(choice, null) : choice;
  }
  const effortId = capability?.reasoningEffortConfigId ?? 'reasoning_effort';
  const changed =
    (config.modelId !== undefined && config.modelId !== choice.modelId) ||
    (config.modeId !== undefined && config.modeId !== choice.modeId) ||
    Object.entries(config.configOptionValues ?? {}).some(([id, value]) => {
      if (id === effortId && choice.effort !== undefined)
        return value !== choice.effort;
      return value !== choice.configOptionValues?.[id];
    });
  return changed ? selectedRoleChoice(choice, null) : choice;
}

export function roleOptionSummary(role: AgentRoleOption) {
  return [
    role.agentName,
    role.runConfig.modelId,
    role.runConfig.modeId,
    ...Object.values(role.runConfig.configOptionValues ?? {}).filter(
      (value) => typeof value === 'string',
    ),
  ]
    .filter(Boolean)
    .join(' · ');
}
