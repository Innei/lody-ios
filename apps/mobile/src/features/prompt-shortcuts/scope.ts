import type { Catalog } from '@lody/cloud-runtime/models/catalog';
import type { CreationOptions } from '@lody/cloud-runtime/models/send';
import {
  shortcutComposerScope,
  type PromptShortcutProject,
} from '@lody/cloud-runtime/models/prompt-shortcuts';

export type PromptShortcutScopeOptions = {
  projects: { id: string; title: string; value: PromptShortcutProject }[];
  machines: { id: string; title: string }[];
  providers: { id: string; title: string }[];
};
export function promptShortcutScopeOptions(
  catalog: Catalog,
  agents: CreationOptions['agents'] = [],
): PromptShortcutScopeOptions {
  const providers = new Map<string, { id: string; title: string }>();
  for (const source of [...agents, ...catalog.sessions]) {
    if (!source.cliType || !source.agentType) continue;
    const id = `${source.cliType}:${source.agentType}`;
    providers.set(id, { id, title: source.agentType });
  }
  return {
    projects: catalog.projects.flatMap((project) => {
      const value = shortcutComposerScope({
        projectId: project.id,
        machineId: project.machineId,
      }).project;
      return value ? [{ id: project.id, title: project.name, value }] : [];
    }),
    machines: catalog.machineIds.map((id) => ({
      id,
      title: catalog.machineNames?.[id] ?? id,
    })),
    providers: [...providers.values()],
  };
}
