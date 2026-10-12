import { teamRequest } from '@lody-ios/kit';
import type {
  TeamSource,
  TeamState,
  TeamMember,
  TeamInvitation,
  TeamOwnerState,
  TeamJoinPreview,
  TeamInvitePreview,
  TeamSeatPreview,
} from '../models/team.ts';

export const teamSource: TeamSource = {
  request: async (scope, command) =>
    JSON.parse(
      await teamRequest(
        JSON.stringify({
          userId: scope.userId,
          workspaceId: scope.workspaceId,
          operation: command.operation,
          args: command.args ?? {},
        }),
      ),
    ),
};

function invalid(): never {
  throw new Error('team_invalid_response');
}
function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    return invalid();
  return value as Record<string, unknown>;
}
function string(value: unknown): string {
  if (typeof value !== 'string' || !value.trim() || value.length > 4096)
    return invalid();
  return value;
}
function number(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0)
    return invalid();
  return value;
}
function boolean(value: unknown): boolean {
  if (typeof value !== 'boolean') return invalid();
  return value;
}
function nullableNumber(value: unknown): number | null {
  return value === null ? null : number(value);
}
export function parseTeamMember(value: unknown): TeamMember {
  const row = object(value);
  const email = string(row.email);
  let image: string | undefined;
  if (typeof row.image === 'string') {
    try {
      const url = new URL(row.image);
      if (url.protocol === 'https:' && !url.username && !url.password)
        image = url.href;
    } catch {
      /* Ignore an invalid avatar without losing the member. */
    }
  }
  return {
    id: string(row.id),
    userId: string(row.userId),
    role: string(row.role),
    name: typeof row.name === 'string' && row.name.trim() ? row.name : email,
    email,
    image,
  };
}
export function parseTeamMembers(value: unknown) {
  const data = object(value);
  if (!Array.isArray(data.members) || data.members.length > 50)
    return invalid();
  const total = number(data.total);
  if (!Number.isSafeInteger(total) || total < data.members.length)
    return invalid();
  const members = data.members.map(parseTeamMember);
  if (new Set(members.map((member) => member.id)).size !== members.length)
    return invalid();
  return { members, total };
}
export function parseTeamInvitations(value: unknown): TeamInvitation[] {
  if (!Array.isArray(value)) return invalid();
  return value
    .map((entry) => {
      const row = object(entry);
      const expiresAt = row.expiresAt;
      if (
        (typeof expiresAt !== 'string' && typeof expiresAt !== 'number') ||
        !Number.isFinite(new Date(expiresAt).getTime())
      )
        return invalid();
      return {
        id: string(row.id),
        organizationId: string(row.organizationId),
        email: string(row.email),
        role: string(row.role),
        status: string(row.status),
        expiresAt,
        organizationName:
          typeof row.organizationName === 'string'
            ? row.organizationName
            : undefined,
      };
    })
    .filter(
      (row) =>
        row.status === 'pending' &&
        new Date(row.expiresAt).getTime() > Date.now(),
    );
}
function parseSeat(value: unknown): TeamSeatPreview | null {
  if (value === null) return null;
  const row = object(value);
  if (
    row.status === 'not_billed' &&
    (row.reason === 'free' || row.reason === 'covered')
  )
    return { status: 'not_billed', reason: row.reason };
  if (
    row.status !== 'billed' ||
    !['month', 'year'].includes(String(row.interval))
  )
    return invalid();
  return {
    status: 'billed',
    interval: row.interval as 'month' | 'year',
    unitAmount: number(row.unitAmount),
    proratedAmount: nullableNumber(row.proratedAmount),
    currentPeriodEnd: nullableNumber(row.currentPeriodEnd),
    seatCount: number(row.seatCount),
    nextSeatCount: number(row.nextSeatCount),
    nextRenewalAmount: number(row.nextRenewalAmount),
  };
}
export function parseTeamState(value: unknown, userId: string): TeamState {
  const row = object(value),
    viewer = parseTeamMember(row.viewer);
  if (viewer.userId !== userId) return invalid();
  let limit: TeamState['limit'] = null;
  if (row.limit !== null) {
    const item = object(row.limit);
    limit = {
      memberLimit: nullableNumber(item.memberLimit),
      canInvite: boolean(item.canInvite),
      memberCount: number(item.memberCount),
      pendingInvitationCount: number(item.pendingInvitationCount),
    };
  }
  return {
    workspaceName: string(row.workspaceName),
    viewer,
    limit,
    seat: parseSeat(row.seat),
  };
}
export function parseTeamOwnerState(value: unknown): TeamOwnerState {
  const row = object(value);
  let activeLink: TeamOwnerState['activeLink'] = null;
  if (row.activeLink !== null) {
    const link = object(row.activeLink);
    activeLink = {
      id: string(link.id),
      token: string(link.token),
      expiresAt: number(link.expiresAt),
    };
  }
  if (!Array.isArray(row.pendingRequests)) return invalid();
  const pendingRequests = row.pendingRequests.map((entry) => {
    const item = object(entry);
    if (typeof item.reason !== 'string') return invalid();
    return {
      id: string(item.id),
      applicantName: string(item.applicantName),
      applicantEmail: string(item.applicantEmail),
      reason: item.reason,
      createdAt: number(item.createdAt),
    };
  });
  return {
    activeLink,
    pendingRequests,
    hasMorePendingRequests: boolean(row.hasMorePendingRequests),
  };
}
export function parseTeamInvitePreview(value: unknown): TeamInvitePreview {
  const row = object(value);
  if (row.status === 'unavailable') return { status: 'unavailable' };
  if (
    row.status !== 'available' ||
    (row.recipientMatchesSession !== null &&
      typeof row.recipientMatchesSession !== 'boolean')
  )
    return invalid();
  return {
    status: 'available',
    organizationName: string(row.organizationName),
    inviterName: typeof row.inviterName === 'string' ? row.inviterName : null,
    recipientEmailMasked: string(row.recipientEmailMasked),
    recipientMatchesSession: row.recipientMatchesSession,
    role: string(row.role),
  };
}
export function parseTeamJoinPreview(value: unknown): TeamJoinPreview {
  const row = object(value);
  if (row.status === 'unavailable') return { status: 'unavailable' };
  if (row.status !== 'available') return invalid();
  let viewer: Extract<TeamJoinPreview, { status: 'available' }>['viewer'] =
    null;
  if (row.viewer !== null) {
    const item = object(row.viewer);
    let request: NonNullable<
      Extract<TeamJoinPreview, { status: 'available' }>['viewer']
    >['request'] = null;
    if (item.request !== null) {
      const entry = object(item.request);
      if (
        !['pending', 'approved', 'rejected'].includes(String(entry.status)) ||
        typeof entry.reason !== 'string'
      )
        return invalid();
      request = {
        status: entry.status as 'pending' | 'approved' | 'rejected',
        reason: entry.reason,
      };
    }
    viewer = {
      emailVerified: boolean(item.emailVerified),
      alreadyMember: boolean(item.alreadyMember),
      request,
    };
  }
  return {
    status: 'available',
    workspaceName: string(row.workspaceName),
    workspaceSlug:
      typeof row.workspaceSlug === 'string' ? row.workspaceSlug : null,
    expiresAt: number(row.expiresAt),
    viewer,
  };
}
