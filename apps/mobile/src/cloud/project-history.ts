import { localProjects } from '@lody-ios/kit';
import type {
  HistoryRequest,
  HistoryResult,
  HistoryTarget,
} from '../models/project-history.ts';
import { t } from '../lib/i18n/index.ts';

export async function requestProjectHistory(
  workspaceId: string,
  browserId: string,
  history: HistoryRequest,
): Promise<HistoryTarget[] | HistoryResult> {
  try {
    return JSON.parse(
      await localProjects(
        JSON.stringify({ workspaceId, browserId, action: 'history', history }),
      ),
    );
  } catch {
    throw new Error(
      t(
        history.kind === 'import' || history.kind === 'resolve'
          ? 'settings.history.writeFailed'
          : 'settings.history.loadFailed',
      ),
    );
  }
}
export function cancelProjectHistory(workspaceId: string, browserId: string) {
  void localProjects(
    JSON.stringify({ workspaceId, browserId, action: 'cancel' }),
  ).catch(() => {});
}
