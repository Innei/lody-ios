import type { Catalog, Session } from '../../models/catalog.ts';
import { isChatSession } from './inbox.ts';
import { t } from '../../lib/i18n/index.ts';

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
    projectName: isChatSession(session)
      ? creation.projectName || t('inbox.section.chat')
      : project?.name || creation.projectName || '',
    machineName:
      catalog.machineNames?.[session.machineId] || creation.machineName || '',
  };
}
