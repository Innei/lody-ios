import { useCallback, useRef } from 'react';
import { ProjectHistoryView } from '../ProjectHistoryScreen';
import { definePage } from '@/lib/presentation';
import type {
  HistoryResult,
  HistoryService,
  HistoryTarget,
} from '@/models/project-history';
import { t } from '../../lib/i18n/index.ts';

const target: HistoryTarget = {
  machineId: 'studio',
  machineName: 'Studio Mac',
  localProjectId: 'demo',
  projectName: 'Demo Project',
  rootPath: '/Projects/demo',
  provider: { cliType: 'builtin', agentType: 'codex' },
};
function View() {
  const sessions = useRef<HistoryResult['sessions']>([
    { acpSessionId: 'one', title: 'Build the project', status: 'available' },
    { acpSessionId: 'two', title: 'Fix a layout issue', status: 'available' },
    {
      acpSessionId: 'conflict',
      title: 'Changed on both clients',
      status: 'sync_conflict',
      importedSessionId: 'imported-conflict',
    },
    {
      acpSessionId: 'done',
      title: 'Previously imported',
      status: 'imported',
      importedSessionId: 'imported-done',
    },
  ]);
  const failLoad = useRef(true),
    failImport = useRef(true);
  const service = useCallback<HistoryService>(async (request) => {
    if (!__DEV__) throw new Error('Development only');
    if (request.kind === 'targets')
      return [
        target,
        { ...target, provider: { cliType: 'builtin', agentType: 'grok' } },
        {
          ...target,
          localProjectId: 'other',
          projectName: 'Other Project',
          rootPath: '/Projects/other',
        },
        { ...target, machineId: 'laptop', machineName: 'Travel Mac' },
      ];
    if (request.kind === 'sync') {
      await new Promise((resolve) => setTimeout(resolve, 4000));
      if (request.target.provider.agentType === 'grok') return { sessions: [] };
    }
    if (request.kind === 'sync' && failLoad.current) {
      failLoad.current = false;
      throw new Error(t('settings.history.loadFailed'));
    }
    if (request.kind === 'resolve') {
      sessions.current = sessions.current.map((session) =>
        session.acpSessionId === request.acpSessionId
          ? { ...session, status: 'imported' }
          : session,
      );
    }
    if (request.kind === 'import') {
      const failures = request.acpSessionIds
        .filter((id) => id === 'two' && failImport.current)
        .map((acpSessionId) => ({
          acpSessionId,
          message: 'Synthetic import failure',
        }));
      failImport.current = false;
      sessions.current = sessions.current.map((session) =>
        request.acpSessionIds.includes(session.acpSessionId) &&
        !failures.some((item) => item.acpSessionId === session.acpSessionId)
          ? {
              ...session,
              status: 'imported',
              importedSessionId: `imported-${session.acpSessionId}`,
            }
          : session,
      );
      return { sessions: sessions.current, failures };
    }
    return { sessions: sessions.current };
  }, []);
  return <ProjectHistoryView workspaceId="offline-history" service={service} />;
}
export const ProjectHistoryPreviewScreen = definePage({
  id: 'project-history-preview',
  title: t('settings.history.title'),
  Component: View,
  presentation: { headerVariant: 'transparent' },
});
