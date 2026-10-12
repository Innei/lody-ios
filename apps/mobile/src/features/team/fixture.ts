import type {
  TeamCommand,
  TeamInvitation,
  TeamMember,
  TeamOwnerState,
  TeamScope,
  TeamSource,
  TeamState,
} from '../../models/team.ts';
import { canManageMember, teamPermissions } from './model.ts';

export function teamFixture(
  options: {
    role?: string;
    limit?: boolean;
    paid?: boolean;
    paged?: boolean;
    rejectOnce?: 'invite' | 'removeMember' | 'updateRole';
  } = {},
) {
  const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value));
  const viewer: TeamMember = {
    id: 'self',
    userId: 'fixture-user',
    name: 'Alex',
    email: 'alex@example.invalid',
    role: options.role ?? 'owner',
  };
  let members: TeamMember[] = [
    viewer,
    {
      id: 'casey',
      userId: 'casey-user',
      name: 'Casey',
      email: 'casey@example.invalid',
      role: 'member',
    },
    {
      id: 'riley',
      userId: 'riley-user',
      name: 'Riley',
      email: 'riley@example.invalid',
      role: 'admin',
    },
  ];
  if (viewer.role !== 'owner')
    members.push({
      id: 'morgan',
      userId: 'morgan-user',
      name: 'Morgan',
      email: 'morgan@example.invalid',
      role: 'owner',
    });
  if (options.paged)
    members.push(
      ...Array.from({ length: 50 }, (_, index) => ({
        id: `page-${index}`,
        userId: `page-user-${index}`,
        name: `Teammate ${index}`,
        email: `teammate-${index}@example.invalid`,
        role: 'member',
      })),
      {
        id: 'sam',
        userId: 'sam-user',
        name: 'Sam Pagination',
        email: 'sam@example.invalid',
        role: 'member',
      },
    );
  let invitations: TeamInvitation[] = [
    {
      id: 'pending',
      organizationId: 'fixture-workspace',
      email: 'invitee@example.invalid',
      role: 'member',
      status: 'pending',
      expiresAt: '2050-01-01T00:00:00Z',
    },
  ];
  let owner: TeamOwnerState = {
    activeLink: null,
    pendingRequests: [
      {
        id: 'pat-request',
        applicantName: 'Pat',
        applicantEmail: 'pat@example.invalid',
        reason: 'Please add me to review the release.',
        createdAt: 1780000000000,
      },
    ],
    hasMorePendingRequests: false,
  };
  let linkNumber = 0,
    rejected = false,
    left = false,
    accepted = false,
    joinRequest = false;
  const calls: TeamCommand[] = [];
  const state = (): TeamState => ({
    workspaceName: 'Studio',
    viewer: { ...viewer },
    limit: {
      memberLimit: options.limit ? members.length : 10,
      canInvite: !options.limit,
      memberCount: members.length,
      pendingInvitationCount: invitations.length,
    },
    seat: options.paid
      ? {
          status: 'billed',
          interval: 'month',
          unitAmount: 2000,
          proratedAmount: 1000,
          currentPeriodEnd: 2524608000000,
          seatCount: 3,
          nextSeatCount: 4,
          nextRenewalAmount: 8000,
        }
      : { status: 'not_billed', reason: 'free' },
  });
  const source: TeamSource = {
    request: async (scope: TeamScope, command: TeamCommand) => {
      if (
        scope.userId !== 'fixture-user' ||
        (scope.workspaceId && scope.workspaceId !== 'fixture-workspace') ||
        left
      )
        throw new Error('team_scope_changed');
      calls.push(command);
      const permissions = teamPermissions(viewer.role);
      if (
        [
          'invite',
          'invitations',
          'cancelInvitation',
          'updateRole',
          'removeMember',
        ].includes(command.operation) &&
        !permissions.manage
      )
        throw new Error('team_permission_denied');
      if (
        [
          'ownerState',
          'rotateLink',
          'revokeLink',
          'reviewRequest',
          'transfer',
        ].includes(command.operation) &&
        !permissions.owner
      )
        throw new Error('team_permission_denied');
      if (!rejected && command.operation === options.rejectOnce) {
        rejected = true;
        if (command.operation === 'updateRole') viewer.role = 'member';
        throw new Error(
          command.operation === 'updateRole'
            ? 'team_permission_denied'
            : 'team_unavailable',
        );
      }
      switch (command.operation) {
        case 'state':
          return clone(state());
        case 'members':
          return {
            members: clone(
              members.slice(command.args.offset, command.args.offset + 50),
            ),
            total: members.length,
          };
        case 'invitations':
          return clone(invitations);
        case 'ownerState':
          return clone(owner);
        case 'invite':
          if (options.limit)
            throw new Error('free_workspace_member_limit_reached');
          invitations.push({
            id: `invited-${invitations.length}`,
            organizationId: 'fixture-workspace',
            email: command.args.email,
            role: command.args.role,
            status: 'pending',
            expiresAt: '2050-01-01T00:00:00Z',
          });
          return null;
        case 'cancelInvitation':
          invitations = invitations.filter(
            (row) => row.id !== command.args.invitationId,
          );
          return null;
        case 'updateRole':
        case 'removeMember':
        case 'transfer': {
          const target = members.find(
            (row) => row.id === command.args.memberId,
          );
          if (!target || !canManageMember(viewer, target))
            throw new Error('team_permission_denied');
          if (command.operation === 'updateRole')
            target.role = command.args.role;
          if (command.operation === 'removeMember')
            members = members.filter((row) => row.id !== target.id);
          if (command.operation === 'transfer') {
            viewer.role = 'admin';
            target.role = 'owner';
          }
          return null;
        }
        case 'leave':
          if (!permissions.leave) throw new Error('team_owner_must_transfer');
          left = true;
          return null;
        case 'rotateLink':
          owner.activeLink = {
            id: `link-${++linkNumber}`,
            token: `fixture-join-${linkNumber}`,
            expiresAt: 2524608000000,
          };
          return null;
        case 'revokeLink':
          owner.activeLink = null;
          return null;
        case 'reviewRequest': {
          const entry = owner.pendingRequests.find(
            (row) => row.id === command.args.requestId,
          );
          if (!entry) throw new Error('team_permission_denied');
          if (command.args.decision === 'approved')
            members.push({
              id: 'pat',
              userId: 'pat-user',
              name: entry.applicantName,
              email: entry.applicantEmail,
              role: 'member',
            });
          owner.pendingRequests = owner.pendingRequests.filter(
            (row) => row.id !== entry.id,
          );
          return null;
        }
        case 'userInvitations':
          return accepted
            ? []
            : [
                {
                  ...invitations[0],
                  id: 'received',
                  organizationId: 'other-workspace',
                  organizationName: 'Release Review',
                  email: viewer.email,
                },
              ];
        case 'invitePreview':
          return accepted
            ? { status: 'unavailable' }
            : {
                status: 'available',
                organizationName: 'Release Review',
                inviterName: 'Morgan',
                recipientEmailMasked: 'a***@example.invalid',
                recipientMatchesSession:
                  command.args.invitationId !== 'wrong-recipient',
                role: 'member',
              };
        case 'acceptInvitation':
        case 'rejectInvitation':
          accepted = true;
          return null;
        case 'joinPreview':
          return {
            status: 'available',
            workspaceName: 'Release Review',
            workspaceSlug: 'release-review',
            expiresAt: 2524608000000,
            viewer: {
              emailVerified: command.args.token !== 'unverified',
              alreadyMember: false,
              request: joinRequest
                ? { status: 'pending', reason: 'Please add me.' }
                : null,
            },
          };
        case 'submitRequest':
          joinRequest = true;
          return null;
      }
    },
  };
  return { source, calls, state };
}
