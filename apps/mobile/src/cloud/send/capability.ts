import type {
  Capability,
  ConfigOption,
  CreationOptions,
} from '../../models/send.ts';

export const isThoughtLevel = (option: ConfigOption) =>
  option.type === 'select' &&
  (option.category === 'thought_level' || option.id === 'reasoning_effort');

export const extraConfigOptions = (capability?: Capability) =>
  (capability?.configOptions ?? []).filter(
    (option) =>
      !(
        option.type === 'select' &&
        ['model', 'mode'].includes(option.category ?? '')
      ) && !isThoughtLevel(option),
  );

export const validConfigValue = (option: ConfigOption, value: unknown) =>
  option.type === 'boolean'
    ? typeof value === 'boolean'
    : typeof value === 'string' &&
      option.options.some((item) => item.id === value);

export function effortsFor(capability?: Capability, modelId?: string) {
  const model =
    modelId ??
    capability?.configOptions?.find((option) => option.category === 'model')
      ?.currentValue;
  if (typeof model === 'string' && capability?.reasoningEfforts[model])
    return capability.reasoningEfforts[model];
  // Agents without a per-model catalog publish the current ladder in configOptions.
  return (
    capability?.configOptions
      ?.find(isThoughtLevel)
      ?.options.map((option) => option.id) ?? []
  );
}

export function capabilityFor(
  options: Pick<CreationOptions, 'capabilities'> | undefined,
  agent: { machineId: string; cliType: string; agentType: string } | undefined,
) {
  if (!options || !agent) return undefined;
  return options.capabilities.find(
    (c) =>
      c.machineId === agent.machineId &&
      c.cliType === agent.cliType &&
      c.agentType === agent.agentType,
  );
}
