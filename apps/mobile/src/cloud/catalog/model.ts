import { t } from '../../lib/i18n/index.ts';
import { projectRows as rows } from '@lody/cloud-runtime/protocol/catalog';
export { githubProject } from '@lody/cloud-runtime/protocol/catalog';
export type {
  Catalog,
  Project,
  Session,
} from '@lody/cloud-runtime/models/catalog';

export function projectRows(input: Parameters<typeof rows>[0], mode: string) {
  return rows(input, mode, {
    untitled: t('session.untitled'),
    unknown: t('session.statusUnknown'),
    local: t('project.local'),
  });
}
