import { useEffect, useMemo, useRef } from 'react';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { teamSource } from '@/cloud/team';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { t, type TranslationKey } from '@/lib/i18n';
import type { TeamScope, TeamSource } from '@/models/team';
import { teamSession } from './model';

export type TeamPageParams = TeamScope & { source?: TeamSource };

export function useTeamSession(params: TeamPageParams) {
  const { account } = useAuth();
  const { selected } = useCatalog();
  const { cancel } = usePageRuntime();
  const current =
    !!params.source ||
    (!params.userId && !params.workspaceId && !account) ||
    (account?.user.id === params.userId &&
      (!params.workspaceId || selected?.id === params.workspaceId));
  const session = useMemo(
    () => teamSession(params.source ?? teamSource, params),
    [params.source, params.userId, params.workspaceId],
  );
  const alive = useRef(false);
  const currentScope = useRef(current);
  currentScope.current = current;
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
      session.close();
    };
  }, [session]);
  useEffect(() => {
    if (!current) {
      session.close();
      cancel();
    }
  }, [current, session, cancel]);
  return {
    request: session.request,
    active: () => alive.current && currentScope.current,
  };
}

const errors: Record<string, TranslationKey> = {
  free_workspace_member_limit_reached: 'team.limitReached',
  team_permission_denied: 'team.permissionDenied',
  team_scope_changed: 'team.scopeChanged',
  team_signed_out: 'team.signInRequired',
  team_owner_must_transfer: 'team.ownerMustTransfer',
  workspace_transfer_not_owner: 'team.permissionDenied',
  workspace_transfer_invalid_member: 'team.invalidMember',
  workspace_transfer_deleting: 'team.transferUnavailable',
  workspace_transfer_billing_owner_mismatch: 'team.transferSupport',
  workspace_transfer_contact_support: 'team.transferSupport',
  workspace_transfer_billing_busy: 'team.transferBusy',
  workspace_transfer_free_limit: 'team.transferFreeLimit',
  EMAIL_VERIFICATION_REQUIRED_FOR_INVITATION: 'team.verifyEmail',
  YOU_ARE_NOT_THE_RECIPIENT_OF_THE_INVITATION: 'team.recipientMismatch',
  INVITATION_NOT_FOUND: 'team.linkUnavailable',
  INVITATION_ALREADY_ACCEPTED: 'team.alreadyMember',
  YOU_ARE_NOT_ALLOWED_TO_UPDATE_THIS_MEMBER: 'team.permissionDenied',
  YOU_ARE_NOT_ALLOWED_TO_DELETE_THIS_MEMBER: 'team.permissionDenied',
};
export function teamError(cause: unknown) {
  const code = cause instanceof Error ? cause.message : '';
  const key = Object.keys(errors).find((value) => code.includes(value));
  return t(key ? errors[key] : 'team.requestFailed');
}

export function roleTitle(role: string) {
  const keys: Record<string, TranslationKey> = {
    owner: 'team.owner',
    admin: 'team.admin',
    member: 'team.member',
  };
  return keys[role] ? t(keys[role]) : role;
}
