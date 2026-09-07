import { StreamsClient } from '@loro-dev/streams-client';
import { fromByteArray } from 'base64-js';
import { decodeFlock } from '@lody-ios/kit';
import { getStreamsGrant, record } from '../auth/api.ts';
import type { Catalog } from '../../models/catalog.ts';
import { t } from '../../i18n/index.ts';

async function readCatalog(
  grant: { token: string; gatewayBaseUrl: string },
  streamId: string,
  mode: string,
  signal: AbortSignal,
): Promise<Catalog> {
  const client = new StreamsClient({
    url: `${grant.gatewayBaseUrl}/ds/lody/${encodeURIComponent(streamId)}`,
    auth: grant.token,
    timeout: { connectTimeoutMs: 20000, pollTimeoutMs: 20000 },
    retry: { maxAttempts: 1 },
  });
  const bootstrap = await client.bootstrap({ signal });
  // Legacy machines may have no Flock stream; their projects remain in meta.
  if (!bootstrap.ok && bootstrap.result.code === 'not_found' && mode !== 'meta')
    return { projects: [], sessions: [], machineIds: [] };
  if (!bootstrap.ok)
    throw new Error(
      t('workspace.error.bootstrapFailed', { code: bootstrap.result.code }),
    );
  const data = bootstrap.result;
  const snapshot =
    data.snapshotOffset !== '-1' ? data.snapshot?.body : undefined;
  const updates = data.updates.map((p) => p.body);
  let size =
    (snapshot?.byteLength ?? 0) + updates.reduce((n, p) => n + p.length, 0);
  let offset = data.nextOffset,
    complete = data.upToDate;
  // ponytail: bounded one-shot read; use incremental sync for catalogs larger than 8 MiB / 100 pages.
  for (
    let page = 0;
    !complete && page < 100 && size <= 8 * 1024 * 1024;
    page++
  ) {
    const response = await client.read({ offset, signal });
    if (!response.ok)
      throw new Error(
        t('workspace.error.incrementalFailed', { code: response.result.code }),
      );
    const next = response.result;
    if (next.nextOffset === offset && !next.upToDate)
      throw new Error(t('workspace.error.cursorStalled'));
    updates.push(next.payload.body);
    size += next.payload.body.length;
    offset = next.nextOffset;
    complete = next.upToDate;
  }
  if (!complete || size > 8 * 1024 * 1024)
    throw new Error(t('workspace.error.tooLarge'));
  if (signal.aborted) throw new Error(t('common.cancelled'));
  const result = record(
    JSON.parse(
      await decodeFlock(
        snapshot ? fromByteArray(snapshot) : '',
        updates.map(fromByteArray),
        mode,
      ),
    ),
  );
  if (signal.aborted) throw new Error(t('common.cancelled'));
  if (
    !Array.isArray(result.projects) ||
    !Array.isArray(result.sessions) ||
    !Array.isArray(result.machineIds)
  )
    throw new Error(t('workspace.error.invalidCatalog'));
  return result as unknown as Catalog;
}
export async function loadCatalog(
  token: string,
  workspaceId: string,
  signal: AbortSignal,
): Promise<Catalog> {
  const grant = await getStreamsGrant(token, workspaceId, signal);
  const meta = await readCatalog(grant, `${workspaceId}:meta`, 'meta', signal);
  const projects = new Map(meta.projects.map((p) => [p.id, p]));
  for (const machineId of meta.machineIds) {
    const machine = await readCatalog(
      grant,
      `${workspaceId}:mf:${machineId}`,
      machineId,
      signal,
    );
    for (const project of machine.projects) projects.set(project.id, project);
  }
  return {
    ...meta,
    projects: [...projects.values()].sort((a, b) =>
      a.name.localeCompare(b.name),
    ),
    sessions: meta.sessions.sort((a, b) =>
      b.createdAt.localeCompare(a.createdAt),
    ),
  };
}
