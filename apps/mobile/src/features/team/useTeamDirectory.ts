import { useEffect, useState } from 'react';
import { parseTeamMembers, teamSource } from '../../cloud/team';
import type { TeamScope } from '../../models/team';

const empty = { senders: {}, showSenderIdentity: false };

export function useTeamDirectory(scope?: TeamScope) {
  const userId = scope?.userId ?? '';
  const workspaceId = scope?.workspaceId ?? '';
  const workspaceName = scope?.workspaceName ?? '';
  const key = JSON.stringify([userId, workspaceId]);
  const [directory, setDirectory] = useState({
    key: '',
    senders: {} as Record<string, string>,
    total: 0,
  });
  useEffect(() => {
    if (!userId || !workspaceId) return;
    let active = true;
    void (async () => {
      const senders: Record<string, string> = {};
      let offset = 0;
      let total = 0;
      do {
        const page = parseTeamMembers(
          await teamSource.request(
            { userId, workspaceId, workspaceName },
            { operation: 'members', args: { offset } },
          ),
        );
        if (!active) return;
        total = page.total;
        if (!page.members.length && offset < total)
          throw new Error('team_incomplete_directory');
        for (const member of page.members) senders[member.userId] = member.name;
        offset += page.members.length;
      } while (offset < total);
      if (active) setDirectory({ key, senders, total });
    })().catch(() => {
      if (active) setDirectory({ key, senders: {}, total: 0 });
    });
    return () => {
      active = false;
    };
  }, [userId, workspaceId, workspaceName]);
  if (directory.key !== key || directory.total < 2) return empty;
  return { senders: directory.senders, showSenderIdentity: true };
}
