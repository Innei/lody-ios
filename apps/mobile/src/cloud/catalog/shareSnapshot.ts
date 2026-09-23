import { publishShareSnapshot, sessionCreationOptions } from '@lody-ios/kit';
import { isChatProjectId } from '../../features/sessions/inbox';
import { createPrefsKey } from '../../features/sessions/createPrefs';
import type { Catalog } from '../../models/catalog';
import type { CreatePrefs, CreationOptions } from '../../models/send';
import { readLocal } from '../kv';

/** Called by the existing catalog owner. No additional subscription or replica. */
export async function refreshShareSnapshot(
  userId: string,
  workspaceId: string,
  catalog: Catalog,
  active: () => boolean,
) {
  const [raw, prefs] = await Promise.all([
    sessionCreationOptions(JSON.stringify({ workspaceId })),
    readLocal<CreatePrefs>(createPrefsKey(userId, workspaceId)),
  ]);
  if (!active()) return;
  const options: CreationOptions = JSON.parse(raw);
  await publishShareSnapshot(
    JSON.stringify({
      userId,
      workspaceId,
      updatedAt: Date.now(),
      projects: catalog.projects.filter(
        (project) => !isChatProjectId(project.id),
      ),
      prefs: prefs ?? {},
      options: { chat: options },
      context: prefs?.context ?? 'chat',
    }),
  );
}
