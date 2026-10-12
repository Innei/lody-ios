import type {
  TeamMember,
  TeamSource,
  TeamScope,
  TeamCommand,
} from '../../models/team.ts';

export function teamPermissions(role: string) {
  const roles = role.split(',').map((value) => value.trim());
  const owner = roles.includes('owner');
  return { owner, manage: owner || roles.includes('admin'), leave: !owner };
}

export function canManageMember(viewer: TeamMember, member: TeamMember) {
  return (
    teamPermissions(viewer.role).manage &&
    ['member', 'admin'].includes(member.role) &&
    viewer.userId !== member.userId
  );
}

export function transferCandidates(viewer: TeamMember, members: TeamMember[]) {
  return members.filter(
    (member) =>
      member.userId !== viewer.userId &&
      ['member', 'admin'].includes(member.role),
  );
}

export function searchMembers(members: TeamMember[], search: string) {
  const query = search.trim().toLocaleLowerCase();
  return members.filter((member) =>
    [member.name, member.email, member.role].some((text) =>
      text.toLocaleLowerCase().includes(query),
    ),
  );
}

export function invitationUrl(id: string) {
  return `https://lody.ai/invite/${encodeURIComponent(id)}`;
}

export function joinUrl(token: string) {
  return `https://lody.ai/join/${encodeURIComponent(token)}`;
}

export function parseTeamLink(
  text: string,
): { kind: 'invite' | 'join'; id: string } | null {
  try {
    const url = new URL(text.trim());
    if (
      url.origin !== 'https://lody.ai' ||
      url.username ||
      url.password ||
      url.search ||
      url.hash
    )
      return null;
    const match = /^\/(invite|join)\/([a-zA-Z0-9_-]{1,256})\/?$/.exec(
      url.pathname,
    );
    if (!match) return null;
    return { kind: match[1] as 'invite' | 'join', id: match[2] };
  } catch {
    return null;
  }
}

// Closing a page fences late responses; uncertain writes are never replayed.
export function teamSession(source: TeamSource, scope: TeamScope) {
  let closed = false;
  return {
    close: () => {
      closed = true;
    },
    request: async (command: TeamCommand) => {
      if (closed) throw new Error('team_scope_changed');
      const value = await source.request(scope, command);
      if (closed) throw new Error('team_scope_changed');
      return value;
    },
  };
}
