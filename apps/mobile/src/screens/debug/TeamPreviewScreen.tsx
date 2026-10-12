import { NativeGroupedList } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { teamFixture } from '@/features/team/fixture';
import { TeamScreen } from '../TeamScreen';
import { TeamJoinScreen } from '../TeamJoinScreen';

function View() {
  const { push } = usePageRuntime();
  const cases = [
    { id: 'owner', title: 'Owner', role: 'owner' },
    { id: 'admin', title: 'Administrator', role: 'admin' },
    { id: 'member', title: 'Member', role: 'member' },
    { id: 'limit', title: 'Member limit', limit: true },
    { id: 'paid', title: 'Seat preview', paid: true },
    { id: 'paged', title: 'Paged members', paged: true },
    {
      id: 'invite-failure',
      title: 'Rejected invitation',
      rejectOnce: 'invite' as const,
    },
    {
      id: 'remove-failure',
      title: 'Rejected removal',
      rejectOnce: 'removeMember' as const,
    },
    {
      id: 'role-loss',
      title: 'Permission changed',
      rejectOnce: 'updateRole' as const,
    },
    { id: 'join', title: 'Join workspace' },
    { id: 'wrong-recipient', title: 'Wrong invitation recipient' },
    { id: 'unverified', title: 'Unverified join applicant' },
  ];
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      sections={[
        {
          id: 'team-fixtures',
          rows: cases.map((entry) => ({
            id: `team-fixture:${entry.id}`,
            title: entry.title,
            action: true,
            disclosure: true,
            navigates: true,
          })),
        },
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        const entry = cases.find((value) => `team-fixture:${value.id}` === id);
        if (!entry) return;
        const { source } = teamFixture(entry);
        if (entry.id === 'join')
          void push(TeamJoinScreen, { userId: 'fixture-user', source });
        else if (entry.id === 'wrong-recipient')
          void push(TeamJoinScreen, {
            userId: 'fixture-user',
            source,
            kind: 'invite',
            id: entry.id,
          });
        else if (entry.id === 'unverified')
          void push(TeamJoinScreen, {
            userId: 'fixture-user',
            source,
            kind: 'join',
            id: entry.id,
          });
        else
          void push(TeamScreen, {
            userId: 'fixture-user',
            workspaceId: 'fixture-workspace',
            workspaceName: 'Studio',
            source,
          });
      }}
    />
  );
}
export const TeamPreviewScreen = definePage({
  id: 'team-preview',
  title: 'Team management',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
