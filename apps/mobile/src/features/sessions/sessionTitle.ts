import type { Catalog, Session } from '../../models/catalog.ts';

type CreationNames = {
  projectName?: string;
  machineName?: string;
};

export function sessionTitleDetails(
  catalog: Catalog,
  session: Session,
  creation: CreationNames = {},
) {
  const project = catalog.projects.find(
    (item) => item.id === session.projectId,
  );
  return {
    project,
    projectName: project?.name || creation.projectName || '',
    machineName:
      catalog.machineNames?.[session.machineId] || creation.machineName || '',
  };
}
