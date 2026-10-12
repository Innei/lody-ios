export type TeamRole = 'member' | 'admin';
export type TeamMember = {
  id: string;
  userId: string;
  name: string;
  email: string;
  role: string;
  image?: string;
};
export type TeamInvitation = {
  id: string;
  organizationId: string;
  organizationName?: string;
  email: string;
  role: string;
  status: string;
  expiresAt: string | number;
};
export type TeamScope = {
  userId: string;
  workspaceId: string;
  workspaceName: string;
};
export type TeamLimit = {
  memberLimit: number | null;
  canInvite: boolean;
  memberCount: number;
  pendingInvitationCount: number;
};
export type TeamSeatPreview =
  | { status: 'not_billed'; reason: 'free' | 'covered' }
  | {
      status: 'billed';
      interval: 'month' | 'year';
      unitAmount: number;
      proratedAmount: number | null;
      currentPeriodEnd: number | null;
      seatCount: number;
      nextSeatCount: number;
      nextRenewalAmount: number;
    };
export type TeamState = {
  workspaceName: string;
  viewer: TeamMember;
  limit: TeamLimit | null;
  seat: TeamSeatPreview | null;
};
export type TeamOwnerState = {
  activeLink: null | { id: string; token: string; expiresAt: number };
  pendingRequests: {
    id: string;
    applicantName: string;
    applicantEmail: string;
    reason: string;
    createdAt: number;
  }[];
  hasMorePendingRequests: boolean;
};
export type TeamInvitePreview =
  | { status: 'unavailable' }
  | {
      status: 'available';
      organizationName: string;
      inviterName: string | null;
      recipientEmailMasked: string;
      recipientMatchesSession: boolean | null;
      role: string;
    };
export type TeamJoinPreview =
  | { status: 'unavailable' }
  | {
      status: 'available';
      workspaceName: string;
      workspaceSlug: string | null;
      expiresAt: number;
      viewer: null | {
        emailVerified: boolean;
        alreadyMember: boolean;
        request: null | {
          status: 'pending' | 'approved' | 'rejected';
          reason: string;
        };
      };
    };
export type TeamCommand =
  | {
      operation:
        'state' | 'invitations' | 'userInvitations' | 'ownerState' | 'leave';
      args?: never;
    }
  | { operation: 'members'; args: { offset: number } }
  | { operation: 'invite'; args: { email: string; role: TeamRole } }
  | {
      operation:
        | 'cancelInvitation'
        | 'invitePreview'
        | 'acceptInvitation'
        | 'rejectInvitation';
      args: { invitationId: string };
    }
  | { operation: 'updateRole'; args: { memberId: string; role: TeamRole } }
  | { operation: 'removeMember' | 'transfer'; args: { memberId: string } }
  | { operation: 'rotateLink'; args: { expiresInDays: 7 | 30 | 90 } }
  | { operation: 'revokeLink'; args: { linkId: string } }
  | {
      operation: 'reviewRequest';
      args: { requestId: string; decision: 'approved' | 'rejected' };
    }
  | { operation: 'joinPreview'; args: { token: string } }
  | { operation: 'submitRequest'; args: { token: string; reason: string } };
export type TeamSource = {
  request: (scope: TeamScope, command: TeamCommand) => Promise<unknown>;
};
