import { useEffect, useMemo } from 'react';
import {
  initialInboxProjectSort,
  sessionCreationOptions,
  runOptions,
  shareWriteCatalog,
  shareWriteOptions,
} from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { isChatProjectId, sortCatalogProjects } from '../sessions/inbox';

const PREFETCH = 10;

export function ShareSnapshot() {
  const { account } = useAuth();
  const { catalog, selected, loading, connected } = useCatalog();
  const userId = account?.user.id ?? '';
  const workspaceId = selected?.id ?? '';
  const projects = useMemo(
    () =>
      sortCatalogProjects(
        catalog.projects.filter((project) => !isChatProjectId(project.id)),
        catalog.sessions,
        initialInboxProjectSort,
      ),
    [catalog.projects, catalog.sessions],
  );

  const payload =
    userId && workspaceId
      ? JSON.stringify({
          userId,
          workspaceId,
          projects,
          machineNames: catalog.machineNames ?? {},
        })
      : '';
  useEffect(() => {
    if (!payload) return;
    try {
      shareWriteCatalog(payload);
    } catch {}
  }, [payload]);

  const targets = projects.slice(0, PREFETCH).map((project) => project.id);
  const prefetch =
    userId && workspaceId && !loading && connected
      ? JSON.stringify([workspaceId, ...targets])
      : '';
  useEffect(() => {
    if (!prefetch) return;
    const [workspace, ...ids] = JSON.parse(prefetch) as string[];
    let active = true;
    void (async () => {
      for (const projectId of [undefined, ...ids]) {
        if (!active) return;
        try {
          const raw = await sessionCreationOptions(
            JSON.stringify({
              workspaceId: workspace,
              ...(projectId ? { projectId } : {}),
            }),
          );
          const options = JSON.parse(raw);
          options.runOptions = JSON.parse(
            await runOptions(
              JSON.stringify({
                workspaceId: workspace,
                userId,
                ...(projectId ? { projectId } : {}),
              }),
            ),
          );
          if (active)
            shareWriteOptions(projectId ?? 'chat', JSON.stringify(options));
        } catch {}
      }
    })();
    return () => {
      active = false;
    };
  }, [prefetch]);
  return null;
}
