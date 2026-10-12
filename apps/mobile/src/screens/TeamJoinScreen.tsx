import {
  use,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { Alert, Linking, TextInput } from 'react-native';
import {
  NativeGroupedList,
  NativeNavigationHeader,
  NativePressable,
  type NativeListSection,
} from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import {
  parseTeamInvitations,
  parseTeamInvitePreview,
  parseTeamJoinPreview,
} from '@/cloud/team';
import { invitationUrl, joinUrl, parseTeamLink } from '@/features/team/model';
import { roleTitle, teamError, useTeamSession } from '@/features/team/useTeam';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { definePage } from '@/lib/presentation';
import { SheetHeaderContext } from '@/lib/presentation/SheetStack';
import { t } from '@/lib/i18n';
import { usePalette } from '@/lib/theme/palette';
import type {
  TeamInvitation,
  TeamInvitePreview,
  TeamJoinPreview,
  TeamSource,
} from '@/models/team';
import { Screen } from '@/ui/Screen';
import { FormGroup, formInputStyle } from '@/ui/FormGroup';
import { AppText } from '@/ui/AppText';

type Params = {
  kind?: 'invite' | 'join';
  id?: string;
  userId?: string;
  source?: TeamSource;
  inbox?: boolean;
};
function View() {
  const { params } = usePageRuntime<Params>();
  const { account } = useAuth();
  const userId = params.userId ?? account?.user.id ?? '';
  return <Content key={`${userId}:${params.kind ?? ''}:${params.id ?? ''}`} />;
}
function Content() {
  const { params, present } = usePageRuntime<Params>();
  const sheetHeader = use(SheetHeaderContext);
  const auth = useAuth();
  const userId = params.userId ?? auth.account?.user.id ?? '';
  const { request, active } = useTeamSession({
    userId,
    workspaceId: '',
    workspaceName: '',
    source: params.source,
  });
  const colors = usePalette();
  const [link, setLink] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [invitations, setInvitations] = useState<TeamInvitation[]>([]);
  const [invite, setInvite] = useState<TeamInvitePreview | null>(null);
  const [join, setJoin] = useState<TeamJoinPreview | null>(null);
  const running = useRef(false);
  const title = t(
    params.kind === 'invite' ? 'team.acceptInvitation' : 'team.joinWorkspace',
  );
  const load = async () => {
    if (!userId || running.current) return;
    running.current = true;
    setBusy(true);
    setError('');
    try {
      if (params.kind === 'invite' && params.id) {
        const value = parseTeamInvitePreview(
          await request({
            operation: 'invitePreview',
            args: { invitationId: params.id },
          }),
        );
        if (active()) setInvite(value);
      } else if (params.kind === 'join' && params.id) {
        const value = parseTeamJoinPreview(
          await request({
            operation: 'joinPreview',
            args: { token: params.id },
          }),
        );
        if (active()) {
          setJoin(value);
          if (
            value.status === 'available' &&
            value.viewer?.request?.status === 'rejected'
          )
            setReason(value.viewer.request.reason);
        }
      } else {
        const value = parseTeamInvitations(
          await request({ operation: 'userInvitations' }),
        );
        if (active()) setInvitations(value);
      }
    } catch (cause) {
      if (active()) setError(teamError(cause));
    } finally {
      running.current = false;
      if (active()) setBusy(false);
    }
  };
  const submit = async (reject = false) => {
    if (!params.id || running.current) return;
    if (
      params.kind === 'invite' &&
      (invite?.status !== 'available' ||
        invite.recipientMatchesSession !== true)
    )
      return;
    if (
      params.kind === 'join' &&
      (!reason.trim() ||
        join?.status !== 'available' ||
        !join.viewer?.emailVerified ||
        join.viewer.alreadyMember ||
        join.viewer.request?.status === 'pending')
    )
      return;
    running.current = true;
    setBusy(true);
    setError('');
    try {
      if (params.kind === 'invite')
        await request({
          operation: reject ? 'rejectInvitation' : 'acceptInvitation',
          args: { invitationId: params.id },
        });
      else
        await request({
          operation: 'submitRequest',
          args: { token: params.id, reason: reason.trim() },
        });
      if (!active()) return;
      setNotice(
        t(
          params.kind === 'invite'
            ? 'team.invitationAccepted'
            : 'team.requestSubmitted',
        ),
      );
      if (reject) setNotice(t('team.invitationRejected'));
      if (params.kind === 'invite' && !reject && !params.source)
        void auth.restore();
      if (params.kind === 'join') {
        const value = parseTeamJoinPreview(
          await request({
            operation: 'joinPreview',
            args: { token: params.id },
          }),
        );
        if (active()) setJoin(value);
      }
    } catch (cause) {
      if (active()) setError(teamError(cause));
    } finally {
      running.current = false;
      if (active()) setBusy(false);
    }
  };
  useEffect(() => {
    void load();
  }, [request, params.kind, params.id, userId]);
  const right = useMemo(
    () => [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'arrow.clockwise' },
        accessibilityLabel: t('team.refresh'),
        disabled: busy || !userId,
        onPress: () => void load(),
      },
    ],
    [busy, userId, request],
  );
  useSheetHeader(right);
  let stateMessage = '';
  if (!userId) stateMessage = t('team.signInRequired');
  if (invite?.status === 'unavailable' || join?.status === 'unavailable')
    stateMessage = t('team.linkUnavailable');
  if (invite?.status === 'available' && invite.recipientMatchesSession !== true)
    stateMessage = t('team.recipientMismatch');
  if (join?.status === 'available') {
    const viewer = join.viewer;
    if (!viewer) stateMessage = t('team.signInRequired');
    else if (viewer.alreadyMember || viewer.request?.status === 'approved')
      stateMessage = t('team.alreadyMember');
    else if (!viewer.emailVerified) stateMessage = t('team.verifyEmail');
    else if (viewer.request?.status === 'pending')
      stateMessage = t('team.requestPending');
    else if (viewer.request?.status === 'rejected')
      stateMessage = t('team.requestRejected');
  }
  const canInvite =
    invite?.status === 'available' &&
    invite.recipientMatchesSession === true &&
    !notice;
  const canRequest =
    join?.status === 'available' &&
    join.viewer?.emailVerified &&
    !join.viewer.alreadyMember &&
    join.viewer.request?.status !== 'pending' &&
    join.viewer.request?.status !== 'approved';
  const openLink = () => {
    const parsed = parseTeamLink(link);
    if (!parsed) {
      setError(t('team.invalidLink'));
      return;
    }
    void present(
      TeamJoinScreen,
      { kind: parsed.kind, id: parsed.id, userId, source: params.source },
      { title: t('team.joinWorkspace') },
    ).then(() => {
      if (active()) void load();
    });
  };
  const sections: NativeListSection[] = [];
  if (!params.kind) {
    sections.push({
      id: 'team-received-invitations',
      header: t('team.receivedInvitations'),
      rows: invitations.map((entry) => ({
        id: `received:${entry.id}`,
        title: entry.organizationName ?? t('team.workspace'),
        subtitle: entry.email,
        value: roleTitle(entry.role),
        action: !busy,
        disclosure: true,
        navigates: true,
      })),
      footer: invitations.length ? undefined : t('team.noInvitations'),
    });
  }
  if (stateMessage)
    sections.push({
      id: 'team-entry-state',
      rows: [{ id: 'team-entry-state', title: stateMessage, action: false }],
    });
  if (notice)
    sections.push({
      id: 'team-entry-success',
      rows: [{ id: 'team-entry-success', title: notice, action: false }],
    });
  if (canInvite)
    sections.push({
      id: 'team-invite-preview',
      header: invite.organizationName,
      footer: invite.recipientEmailMasked,
      rows: [
        {
          id: 'team-accept',
          title: t('team.acceptInvitation'),
          value: roleTitle(invite.role),
          action: !busy,
        },
        {
          id: 'team-reject-invitation',
          title: t('team.rejectInvitation'),
          destructive: true,
          action: !busy,
        },
      ],
    });
  if (params.kind && params.id)
    sections.push({
      id: 'team-official-link',
      rows: [
        {
          id: 'team-open-official',
          title: t('team.openOfficial'),
          action: !busy,
        },
      ],
    });
  if (error)
    sections.push({
      id: 'team-entry-error',
      footer: error,
      rows: [
        { id: 'team-entry-retry', title: t('common.retry'), action: !busy },
      ],
    });
  const onRow = (id: string) => {
    if (id === 'team-entry-retry') void load();
    if (id === 'team-accept') void submit();
    if (id === 'team-reject-invitation')
      Alert.alert(t('team.rejectInvitation'), t('team.rejectInviteHint'), [
        { text: t('common.cancel'), style: 'cancel' },
        {
          text: t('team.reject'),
          style: 'destructive',
          onPress: () => void submit(true),
        },
      ]);
    if (id === 'team-open-official' && params.kind && params.id)
      void Linking.openURL(
        params.kind === 'invite'
          ? invitationUrl(params.id)
          : joinUrl(params.id),
      ).catch(() => setError(t('team.openFailed')));
    const invitation = invitations.find(
      (entry) => `received:${entry.id}` === id,
    );
    if (invitation)
      void present(
        TeamJoinScreen,
        { kind: 'invite', id: invitation.id, userId, source: params.source },
        { title: t('team.acceptInvitation') },
      ).then(() => {
        if (active()) void load();
      });
  };
  let body: ReactNode;
  if ((!params.kind && !params.inbox) || canRequest) {
    body = (
      <Screen automaticallyAdjustKeyboardInsets scrollToOverflowEnabled>
        {!params.kind ? (
          <FormGroup header={t('team.link')} footer={t('team.linkHint')}>
            <TextInput
              testID="team-join-link"
              accessibilityLabel={t('team.link')}
              value={link}
              onChangeText={setLink}
              autoCapitalize="none"
              autoCorrect={false}
              maxLength={1024}
              returnKeyType="go"
              onSubmitEditing={openLink}
              style={[formInputStyle, { color: colors.label }]}
            />
          </FormGroup>
        ) : null}
        {canRequest && join?.status === 'available' ? (
          <FormGroup header={join.workspaceName} footer={t('team.reasonHint')}>
            <TextInput
              testID="team-join-reason"
              accessibilityLabel={t('team.reason')}
              value={reason}
              onChangeText={setReason}
              editable={!busy}
              multiline
              maxLength={4096}
              style={[formInputStyle, { color: colors.label, minHeight: 100 }]}
            />
          </FormGroup>
        ) : null}
        {stateMessage ? <AppText>{stateMessage}</AppText> : null}
        {notice ? (
          <AppText testID="team-entry-success">{notice}</AppText>
        ) : null}
        {error ? (
          <AppText
            testID="team-entry-error"
            accessibilityRole="alert"
            style={{ color: colors.danger }}
          >
            {error}
          </AppText>
        ) : null}
        <TeamEntryButton
          title={t(params.kind ? 'team.submitRequest' : 'team.openLink')}
          id={params.kind ? 'team-submit-request' : 'team-open-link'}
          disabled={busy || !userId || (canRequest && !reason.trim())}
          onPress={params.kind ? () => void submit() : openLink}
        />
        {!params.kind ? (
          <TeamEntryButton
            id="team-received-invitations"
            title={t('team.receivedInvitations')}
            disabled={busy || !userId}
            onPress={() =>
              void present(
                TeamJoinScreen,
                { ...params, userId, inbox: true },
                { title: t('team.receivedInvitations') },
              )
            }
          />
        ) : null}
      </Screen>
    );
  } else {
    body = (
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        sections={sections}
        refreshing={busy}
        onRefresh={() => void load()}
        placeholder={t(busy ? 'common.loading' : 'team.empty')}
        onRowPress={({ nativeEvent: { id } }) => onRow(id)}
      />
    );
  }
  return (
    <>
      {!sheetHeader ? (
        <NativeNavigationHeader title={title} items={right} />
      ) : null}
      {body}
    </>
  );
}

function TeamEntryButton({
  title,
  id,
  disabled,
  onPress,
}: {
  title: string;
  id: string;
  disabled?: boolean;
  onPress: () => void;
}) {
  const colors = usePalette();
  return (
    <NativePressable
      testID={id}
      accessibilityLabel={title}
      accessibilityRole="button"
      disabled={disabled}
      style={{ minHeight: 44, padding: 12 }}
      onPress={onPress}
    >
      <AppText
        style={{ color: disabled ? colors.tertiaryLabel : colors.accent }}
      >
        {title}
      </AppText>
    </NativePressable>
  );
}
export const TeamJoinScreen = definePage<Params>({
  id: 'team-join',
  title: t('team.joinWorkspace'),
  Component: View,
  parseRouteParams: (params) => {
    if (typeof params.invitationId === 'string')
      return { kind: 'invite', id: params.invitationId };
    if (typeof params.token === 'string')
      return { kind: 'join', id: params.token };
    return {};
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
