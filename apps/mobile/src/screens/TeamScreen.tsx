import { use, useEffect, useMemo, useRef, useState } from 'react';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { Alert, AppState } from 'react-native';
import {
  copyText,
  NativeGroupedList,
  NativeNavigationHeader,
  type NativeListSection,
  type NativeListRow,
} from '@lody-ios/kit';
import {
  parseTeamMembers,
  parseTeamState,
  parseTeamInvitations,
  parseTeamOwnerState,
} from '@/cloud/team';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { definePage } from '@/lib/presentation';
import { SheetHeaderContext } from '@/lib/presentation/SheetStack';
import { t } from '@/lib/i18n';
import { usePalette } from '@/lib/theme/palette';
import {
  canManageMember,
  invitationUrl,
  joinUrl,
  searchMembers,
  teamPermissions,
} from '@/features/team/model';
import {
  useTeamSession,
  teamError,
  roleTitle,
  type TeamPageParams,
} from '@/features/team/useTeam';
import type {
  TeamCommand,
  TeamInvitation,
  TeamMember,
  TeamOwnerState,
  TeamState,
} from '@/models/team';
import { showToast } from '@/ui/toast';
import { TeamFormScreen } from './TeamFormScreen';

type Params = TeamPageParams & { selectOwner?: boolean };
function View() {
  const { params, present, cancel } = usePageRuntime<Params>();
  const sheetHeader = use(SheetHeaderContext);
  const authSession = useTeamSession(params);
  const auth = useAuth();
  const { request, active } = authSession;
  const colors = usePalette();
  const [state, setState] = useState<TeamState | null>(null);
  const [members, setMembers] = useState<TeamMember[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [invitations, setInvitations] = useState<TeamInvitation[]>([]);
  const [owner, setOwner] = useState<TeamOwnerState | null>(null);
  const [search, setSearch] = useState('');
  const [days, setDays] = useState<7 | 30 | 90>(30);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');
  const running = useRef(false);
  const picker = params.selectOwner === true;
  const workspaceName = state?.workspaceName ?? params.workspaceName;
  const permission = teamPermissions(state?.viewer.role ?? '');
  const enabled = !!state && !busy && !error;
  const hasMore = offset < total;
  const title = t(picker ? 'team.newOwner' : 'team.title');

  const read = async () => {
    const next = parseTeamState(
      await request({ operation: 'state' }),
      params.userId,
    );
    if (active()) {
      setState(next);
      setOwner(null);
      setInvitations([]);
    }
    const page = parseTeamMembers(
      await request({ operation: 'members', args: { offset: 0 } }),
    );
    if (page.members.length === 0 && page.total > 0)
      throw new Error('team_invalid_response');
    if (active()) {
      setMembers(page.members);
      setTotal(page.total);
      setOffset(page.members.length);
    }
    if (picker) return;
    const permissions = teamPermissions(next.viewer.role);
    if (permissions.manage) {
      const rows = parseTeamInvitations(
        await request({ operation: 'invitations' }),
      );
      if (active()) setInvitations(rows);
    }
    if (permissions.owner) {
      const value = parseTeamOwnerState(
        await request({ operation: 'ownerState' }),
      );
      if (active()) setOwner(value);
    }
  };
  const load = async () => {
    if (running.current) return;
    running.current = true;
    setBusy(true);
    setError('');
    try {
      await read();
    } catch (cause) {
      if (active()) setError(teamError(cause));
    } finally {
      running.current = false;
      if (active()) setBusy(false);
    }
  };
  const more = async () => {
    if (running.current || !hasMore) return;
    running.current = true;
    setBusy(true);
    setError('');
    try {
      const page = parseTeamMembers(
        await request({ operation: 'members', args: { offset } }),
      );
      if (!page.members.length && page.total > offset)
        throw new Error('team_invalid_response');
      if (active()) {
        setMembers((current) => [
          ...current,
          ...page.members.filter(
            (row) => !current.some((member) => member.id === row.id),
          ),
        ]);
        setTotal(page.total);
        setOffset(offset + page.members.length);
      }
    } catch (cause) {
      if (active()) setError(teamError(cause));
    } finally {
      running.current = false;
      if (active()) setBusy(false);
    }
  };
  const mutate = async (command: TeamCommand) => {
    if (running.current) return;
    running.current = true;
    setBusy(true);
    setError('');
    let committed = false;
    try {
      await request(command);
      committed = true;
      if (!active()) return;
      if (command.operation === 'leave') {
        if (!params.source) {
          await auth.removeWorkspace(params.workspaceId, params.userId);
          void auth.restore();
        }
        cancel();
        return;
      }
      await read();
    } catch (cause) {
      const message = committed
        ? t('team.updatedRefreshFailed')
        : teamError(cause);
      if (!committed) {
        try {
          await read();
        } catch {
          /* Preserve loaded data with a visible failure. */
        }
      }
      if (active()) setError(message);
    } finally {
      running.current = false;
      if (active()) setBusy(false);
    }
  };
  useEffect(() => {
    void load();
  }, [request]);
  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') void load();
    });
    return () => subscription.remove();
  }, [request]);
  useEffect(() => {
    if (search.trim() && hasMore && !busy && !error) void more();
  }, [search, hasMore, busy, error, offset]);

  const openInvite = async () => {
    if (!state || !permission.manage || !enabled) return;
    await present(
      TeamFormScreen,
      { ...params, workspaceName, kind: 'invite', state },
      { title: t('team.invite') },
    );
    if (active()) void load();
  };
  const right = useMemo(() => {
    if (picker || !permission.manage) return [];
    return [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'person.badge.plus' },
        accessibilityLabel: t('team.invite'),
        tintColor: colors.accent,
        disabled: !enabled || state?.limit?.canInvite === false,
        onPress: () => void openInvite(),
      },
    ];
  }, [picker, permission.manage, enabled, state, colors.accent, present]);
  useSheetHeader(right);
  const visible = searchMembers(members, search).filter(
    (member) =>
      !picker ||
      (member.userId !== params.userId &&
        ['admin', 'member'].includes(member.role)),
  );
  const memberRows: NativeListRow[] = visible.map((member) => {
    const editable =
      !!state && !picker && canManageMember(state.viewer, member);
    const options = editable
      ? (['member', 'admin'] as const).map((role) => ({
          id: `role:${role}`,
          title: roleTitle(role),
          selected: member.role === role,
        }))
      : undefined;
    return {
      id: `member:${member.id}`,
      title: member.name,
      subtitle: member.email,
      image: member.image ?? 'person.crop.circle',
      value: roleTitle(member.role),
      accessibilityValue: roleTitle(member.role),
      action: enabled && (picker || editable),
      disclosure: picker,
      navigates: picker,
      options,
      menuActions: editable
        ? [{ id: 'remove', title: t('team.remove'), destructive: true }]
        : undefined,
      actions: editable
        ? [
            {
              id: 'remove',
              title: t('team.remove'),
              symbol: 'person.fill.xmark',
              destructive: true,
            },
          ]
        : undefined,
    };
  });
  const sections: NativeListSection[] = [
    {
      id: 'team-members',
      header: workspaceName,
      footer: hasMore
        ? t('team.searchPartial')
        : t('team.memberCount', { count: total }),
      rows: memberRows,
    },
  ];
  if (!visible.length && !busy)
    sections[0].rows.push({
      id: 'no-members',
      title: t(search.trim() ? 'team.noMatches' : 'team.noCandidates'),
      action: false,
    });
  if (hasMore)
    sections.push({
      id: 'team-more',
      rows: [
        {
          id: 'team-more',
          title: t(busy ? 'common.loading' : 'team.loadMore'),
          action: !busy,
        },
      ],
    });
  if (error)
    sections.push({
      id: 'team-error-section',
      footer: error,
      rows: [{ id: 'team-retry', title: t('common.retry'), action: !busy }],
    });
  if (!picker && state) {
    let limit = t('team.limitUnavailable');
    if (state.limit?.memberLimit === null) limit = t('team.noMemberLimit');
    if (typeof state.limit?.memberLimit === 'number')
      limit = t('team.memberLimit', {
        current: state.limit.memberCount,
        limit: state.limit.memberLimit,
        pending: state.limit.pendingInvitationCount,
      });
    sections.push({
      id: 'team-limit',
      footer:
        state.limit?.canInvite === false ? t('team.limitReached') : undefined,
      rows: [
        {
          id: 'team-limit',
          title: t('team.capacity'),
          subtitle: limit,
          action: false,
        },
      ],
    });
    if (permission.manage)
      sections.push({
        id: 'team-invitations',
        header: t('team.pendingInvitations'),
        rows: invitations.map((invitation) => ({
          id: `invitation:${invitation.id}`,
          title: invitation.email,
          subtitle: t('team.invitationExpires', {
            date: new Date(invitation.expiresAt).toLocaleDateString(),
          }),
          value: roleTitle(invitation.role),
          action: enabled,
          options: [
            { id: 'copy', title: t('team.copyLink'), symbol: 'doc.on.doc' },
            { id: 'revoke', title: t('team.revoke'), destructive: true },
          ],
        })),
        footer: invitations.length ? undefined : t('team.noInvitations'),
      });
    if (permission.owner && owner) {
      const link = owner.activeLink;
      const linkRows: NativeListRow[] = [
        {
          id: 'team-link-expiry',
          title: t('team.linkExpiry'),
          value: t('team.days', { count: days }),
          action: enabled,
          options: ([7, 30, 90] as const).map((value) => ({
            id: `days:${value}`,
            title: t('team.days', { count: value }),
            selected: days === value,
          })),
        },
        {
          id: 'team-create-link',
          title: t(link ? 'team.regenerateLink' : 'team.createLink'),
          action: enabled,
        },
      ];
      if (link)
        linkRows.push(
          {
            id: 'team-copy-join',
            title: t('team.copyLink'),
            value: '',
            action: enabled,
          },
          {
            id: 'team-revoke-join',
            title: t('team.revokeLink'),
            value: '',
            action: enabled,
          },
        );
      sections.push({
        id: 'team-join-link',
        header: t('team.joinLink'),
        rows: linkRows,
        footer: link
          ? t('team.invitationExpires', {
              date: new Date(link.expiresAt).toLocaleDateString(),
            })
          : t('team.joinLinkHint'),
      });
      sections.push({
        id: 'team-requests',
        header: t('team.joinRequests'),
        rows: owner.pendingRequests.map((entry) => ({
          id: `request:${entry.id}`,
          title: entry.applicantName,
          subtitle: entry.applicantEmail,
          action: enabled,
          disclosure: true,
        })),
        footer: owner.pendingRequests.length ? undefined : t('team.noRequests'),
      });
      if (owner.hasMorePendingRequests)
        sections.push({
          id: 'team-more-requests',
          footer: t('team.moreRequestsHint'),
          rows: [
            {
              id: 'team-more-request-refresh',
              title: t('team.refresh'),
              action: !busy,
            },
          ],
        });
    }
    const actions = [];
    if (permission.owner)
      actions.push({
        id: 'team-transfer',
        title: t('team.transfer'),
        subtitle: t('team.ownerMustTransfer'),
        action: enabled,
        disclosure: true,
        navigates: true,
      });
    else
      actions.push({
        id: 'team-leave',
        title: t('team.leave'),
        destructive: true,
        action: enabled,
      });
    sections.push({ id: 'team-membership', rows: actions });
  }
  const confirm = (title: string, message: string, action: () => void) =>
    Alert.alert(title, message, [
      { text: t('common.cancel'), style: 'cancel' },
      { text: title, style: 'destructive', onPress: action },
    ]);
  const copy = (value: string) => {
    try {
      copyText(value);
      showToast(t('team.linkCopied'), 'info');
    } catch {
      setError(t('team.copyFailed'));
    }
  };
  return (
    <>
      {!sheetHeader ? (
        <NativeNavigationHeader title={title} items={right} />
      ) : null}
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        sections={sections}
        searchPlaceholder={t('team.search')}
        onSearchChange={({ nativeEvent }) => setSearch(nativeEvent.text)}
        placeholder={t(busy ? 'common.loading' : 'team.empty')}
        refreshing={busy}
        onRefresh={() => void load()}
        onRowPress={({ nativeEvent: { id } }) => {
          if (id === 'team-more') void more();
          if (id === 'team-retry' || id === 'team-more-request-refresh')
            void load();
          if (id === 'team-transfer')
            void present(
              TeamScreen,
              { ...params, workspaceName, selectOwner: true },
              { title: t('team.newOwner') },
            ).then(() => {
              if (active()) void load();
            });
          if (id.startsWith('member:') && picker && state && permission.owner) {
            const member = members.find((row) => `member:${row.id}` === id);
            if (member)
              void present(
                TeamFormScreen,
                { ...params, workspaceName, kind: 'transfer', member },
                { title: t('team.transfer') },
              ).then((result) => {
                if (result.status === 'completed') cancel();
              });
          }
          if (id === 'team-copy-join' && owner?.activeLink)
            copy(joinUrl(owner.activeLink.token));
          if (id === 'team-create-link') {
            if (owner?.activeLink)
              confirm(
                t('team.regenerateLink'),
                t('team.regenerateHint'),
                () =>
                  void mutate({
                    operation: 'rotateLink',
                    args: { expiresInDays: days },
                  }),
              );
            else
              void mutate({
                operation: 'rotateLink',
                args: { expiresInDays: days },
              });
          }
          if (id === 'team-revoke-join' && owner?.activeLink)
            confirm(
              t('team.revokeLink'),
              t('team.revokeHint'),
              () =>
                void mutate({
                  operation: 'revokeLink',
                  args: { linkId: owner.activeLink!.id },
                }),
            );
          if (id === 'team-leave')
            confirm(
              t('team.leave'),
              t('team.leaveHint', { workspace: workspaceName }),
              () => void mutate({ operation: 'leave' }),
            );
          if (id.startsWith('request:')) {
            const entry = owner?.pendingRequests.find(
              (row) => `request:${row.id}` === id,
            );
            if (entry)
              Alert.alert(
                entry.applicantName,
                `${entry.applicantEmail}\n\n${entry.reason}`,
                [
                  { text: t('common.cancel'), style: 'cancel' },
                  {
                    text: t('team.reject'),
                    style: 'destructive',
                    onPress: () =>
                      void mutate({
                        operation: 'reviewRequest',
                        args: { requestId: entry.id, decision: 'rejected' },
                      }),
                  },
                  {
                    text: t('team.approve'),
                    onPress: () =>
                      void mutate({
                        operation: 'reviewRequest',
                        args: { requestId: entry.id, decision: 'approved' },
                      }),
                  },
                ],
              );
          }
        }}
        onRowAction={({ nativeEvent: { id, actionId } }) => {
          if (id === 'team-link-expiry' && actionId.startsWith('days:'))
            setDays(Number(actionId.slice(5)) as 7 | 30 | 90);
          const member = members.find((row) => `member:${row.id}` === id);
          if (
            member &&
            state &&
            canManageMember(state.viewer, member) &&
            enabled
          ) {
            if (actionId === 'role:member' || actionId === 'role:admin')
              void mutate({
                operation: 'updateRole',
                args: {
                  memberId: member.id,
                  role: actionId.slice(5) as 'member' | 'admin',
                },
              });
            if (actionId === 'remove')
              confirm(
                t('team.remove'),
                t('team.removeHint', { member: member.name }),
                () =>
                  void mutate({
                    operation: 'removeMember',
                    args: { memberId: member.id },
                  }),
              );
          }
          const invitation = invitations.find(
            (row) => `invitation:${row.id}` === id,
          );
          if (invitation && permission.manage && enabled) {
            if (actionId === 'copy') copy(invitationUrl(invitation.id));
            if (actionId === 'revoke')
              confirm(
                t('team.revoke'),
                t('team.revokeHint'),
                () =>
                  void mutate({
                    operation: 'cancelInvitation',
                    args: { invitationId: invitation.id },
                  }),
              );
          }
        }}
      />
    </>
  );
}
export const TeamScreen = definePage<Params>({
  id: 'team',
  title: t('team.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from the selected workspace');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
