import { useMemo, useRef, useState, type ReactNode } from 'react';
import { ActionSheetIOS, StyleSheet, TextInput } from 'react-native';
import { NativeNavigationHeader, NativePressable } from '@lody-ios/kit';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';
import { usePalette } from '@/lib/theme/palette';
import {
  useTeamSession,
  teamError,
  roleTitle,
  type TeamPageParams,
} from '@/features/team/useTeam';
import type { TeamMember, TeamRole, TeamState } from '@/models/team';
import { Screen } from '@/ui/Screen';
import { FormGroup, formInputStyle } from '@/ui/FormGroup';
import { AppText } from '@/ui/AppText';

type Params = TeamPageParams &
  (
    | { kind: 'invite'; state: TeamState }
    | { kind: 'transfer'; member: TeamMember }
  );

function View() {
  const { params, cancel, finish, source } = usePageRuntime<Params>();
  const { request, active } = useTeamSession(params);
  const colors = usePalette();
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<TeamRole>('member');
  const [confirmation, setConfirmation] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [blocked, setBlocked] = useState(false);
  const running = useRef(false);
  const invite = params.kind === 'invite';
  const title = t(invite ? 'team.invite' : 'team.transfer');
  let ready = confirmation === params.workspaceName;
  if (params.kind === 'invite')
    ready =
      /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) &&
      params.state.limit?.canInvite !== false;
  const submit = async () => {
    if (!ready || blocked || running.current) return;
    running.current = true;
    setBusy(true);
    setError('');
    try {
      if (params.kind === 'invite')
        await request({
          operation: 'invite',
          args: { email: email.trim(), role },
        });
      else
        await request({
          operation: 'transfer',
          args: { memberId: params.member.id },
        });
      if (active()) finish();
    } catch (cause) {
      if (active()) {
        setError(teamError(cause));
        const code = cause instanceof Error ? cause.message : '';
        if (
          code.includes('permission') ||
          code.includes('not_owner') ||
          code.includes('member_limit')
        )
          setBlocked(true);
      }
    } finally {
      running.current = false;
      if (active()) setBusy(false);
    }
  };
  const right = useMemo(
    () => [
      {
        type: 'button' as const,
        title,
        accessibilityLabel: title,
        tintColor: colors.accent,
        variant: 'prominent' as const,
        disabled: busy || blocked || !ready,
        onPress: () => void submit(),
      },
    ],
    [
      title,
      colors.accent,
      busy,
      blocked,
      ready,
      email,
      role,
      confirmation,
      request,
    ],
  );
  const left = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('common.cancel'),
        accessibilityLabel: t('common.cancel'),
        disabled: busy,
        onPress: cancel,
      },
    ],
    [busy, cancel],
  );
  useSheetHeader(right, left);
  let seat = '';
  if (params.kind === 'invite' && params.state.seat?.status === 'billed') {
    const value = params.state.seat;
    const usd = (amount: number) =>
      new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD',
      }).format(amount / 100);
    const estimated =
      value.proratedAmount === null
        ? t('team.priceUnknown')
        : usd(value.proratedAmount);
    seat = t('team.seatEstimate', {
      amount: estimated,
      unit: usd(value.unitAmount),
      interval: t(`team.${value.interval}`),
    });
    if (value.currentPeriodEnd !== null)
      seat +=
        '\n' +
        t('team.seatRenewal', {
          date: new Date(value.currentPeriodEnd).toLocaleDateString(),
          amount: usd(value.nextRenewalAmount),
          count: value.nextSeatCount,
        });
  } else if (
    params.kind === 'invite' &&
    params.state.seat?.status === 'not_billed' &&
    params.state.seat.reason === 'covered'
  )
    seat = t('team.seatCovered');
  let fields: ReactNode;
  if (params.kind === 'invite') {
    fields = (
      <>
        <FormGroup
          header={t('team.email')}
          footer={t('team.inviteHint', { workspace: params.workspaceName })}
        >
          <TextInput
            testID="team-email"
            accessibilityLabel={t('team.email')}
            value={email}
            onChangeText={setEmail}
            editable={!busy}
            maxLength={254}
            keyboardType="email-address"
            textContentType="emailAddress"
            autoCapitalize="none"
            autoCorrect={false}
            style={[formInputStyle, { color: colors.label }]}
          />
        </FormGroup>
        <FormGroup
          header={t('team.role')}
          footer={t(role === 'admin' ? 'team.adminHint' : 'team.memberHint')}
        >
          <NativePressable
            testID="team-invite-role"
            accessibilityLabel={t('team.role')}
            accessibilityValue={{ text: roleTitle(role) }}
            disabled={busy}
            style={styles.row}
            onPress={() =>
              ActionSheetIOS.showActionSheetWithOptions(
                {
                  options: [
                    t('common.cancel'),
                    t('team.member'),
                    t('team.admin'),
                  ],
                  cancelButtonIndex: 0,
                },
                (index) => {
                  if (index === 1) setRole('member');
                  if (index === 2) setRole('admin');
                },
              )
            }
          >
            <AppText>{roleTitle(role)}</AppText>
          </NativePressable>
        </FormGroup>
        {seat ? (
          <AppText testID="team-seat-preview" variant="meta">
            {seat}
          </AppText>
        ) : null}
        {params.state.limit?.canInvite === false ? (
          <AppText>{t('team.limitReached')}</AppText>
        ) : null}
      </>
    );
  } else {
    fields = (
      <>
        <AppText>
          {t('team.transferWarning', { member: params.member.name })}
        </AppText>
        <FormGroup
          header={t('team.confirmWorkspace', {
            workspace: params.workspaceName,
          })}
        >
          <TextInput
            testID="team-transfer-confirmation"
            accessibilityLabel={t('team.confirmWorkspace', {
              workspace: params.workspaceName,
            })}
            value={confirmation}
            onChangeText={setConfirmation}
            editable={!busy}
            autoCorrect={false}
            autoCapitalize="none"
            style={[formInputStyle, { color: colors.label }]}
          />
        </FormGroup>
      </>
    );
  }
  return (
    <>
      {source === 'route' ? (
        <NativeNavigationHeader title={title} items={right} leftItems={left} />
      ) : null}
      <Screen
        style={{ backgroundColor: colors.background }}
        automaticallyAdjustKeyboardInsets
      >
        {fields}
        {error ? (
          <AppText
            testID="team-form-error"
            accessibilityRole="alert"
            style={{ color: colors.danger }}
          >
            {error}
          </AppText>
        ) : null}
      </Screen>
    </>
  );
}
export const TeamFormScreen = definePage<Params>({
  id: 'team-form',
  title: t('team.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from team management');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
const styles = StyleSheet.create({
  row: { minHeight: 44, paddingHorizontal: 16, paddingVertical: 11 },
});
