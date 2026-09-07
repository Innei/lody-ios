import type { CreationOptions } from '../../models/send.ts';

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
