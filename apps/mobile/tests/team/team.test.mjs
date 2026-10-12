import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import {
  teamPermissions,
  canManageMember,
  searchMembers,
  parseTeamLink,
  teamSession,
} from '../../src/features/team/model.ts';
import { teamFixture } from '../../src/features/team/fixture.ts';
import {
  removeAccountWorkspace,
  removeWorkspaceState,
} from '../../src/cloud/auth/workspaces.ts';

const bundle = await build({
  entryPoints: [new URL('../../src/cloud/team.ts', import.meta.url).pathname],
  bundle: true,
  write: false,
  format: 'esm',
  platform: 'browser',
  plugins: [
    {
      name: 'native',
      setup(builder) {
        builder.onResolve({ filter: /^@lody-ios\/kit$/ }, () => ({
          path: 'kit',
          namespace: 'fixture',
        }));
        builder.onLoad({ filter: /.*/, namespace: 'fixture' }, () => ({
          contents:
            'export const teamRequest = payload => globalThis.__teamRequest(payload);',
        }));
      },
    },
  ],
});
const protocol = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);
const scope = {
  userId: 'fixture-user',
  workspaceId: 'fixture-workspace',
  workspaceName: 'Studio',
};
const entry = { ...scope, workspaceId: '' };

test('owner/admin/member permissions prevent self, owner, and unknown-role management', () => {
  const owner = { id: 'owner', userId: 'owner', role: 'owner' };
  const admin = { id: 'admin', userId: 'admin', role: 'admin' };
  const member = { id: 'member', userId: 'member', role: 'member' };
  assert.equal(teamPermissions('owner').leave, false);
  assert.equal(teamPermissions('admin').manage, true);
  assert.equal(teamPermissions('auditor').manage, false);
  assert.equal(canManageMember(owner, owner), false);
  assert.equal(canManageMember(admin, owner), false);
  assert.equal(canManageMember(member, admin), false);
  assert.equal(canManageMember(owner, member), true);
  assert.equal(canManageMember(owner, { ...member, role: 'auditor' }), false);
});

test('membership pages can find a later member while searching names, email and roles', async () => {
  const fixture = teamFixture({ paged: true });
  const first = protocol.parseTeamMembers(
    await fixture.source.request(scope, {
      operation: 'members',
      args: { offset: 0 },
    }),
  );
  assert.equal(searchMembers(first.members, 'Sam Pagination').length, 0);
  const second = protocol.parseTeamMembers(
    await fixture.source.request(scope, {
      operation: 'members',
      args: { offset: first.members.length },
    }),
  );
  const all = [...first.members, ...second.members];
  assert.equal(all.length, first.total);
  assert.equal(
    searchMembers(all, 'SAM@EXAMPLE.INVALID')[0].name,
    'Sam Pagination',
  );
  assert.equal(searchMembers(all, 'administrator').length, 0);
  assert.equal(searchMembers(all, 'admin')[0].name, 'Riley');
});

test('native source never needs an RN credential; response parsing excludes unrelated private fields', async () => {
  globalThis.__teamRequest = async (payload) => {
    const request = JSON.parse(payload);
    assert.equal(request.userId, scope.userId);
    assert.equal(request.workspaceId, scope.workspaceId);
    assert.equal('token' in request, false);
    assert.equal('credential' in request, false);
    return JSON.stringify(
      await teamFixture().source.request(scope, {
        operation: 'members',
        args: { offset: 0 },
      }),
    );
  };
  const value = await protocol.teamSource.request(scope, {
    operation: 'members',
    args: { offset: 0 },
  });
  const parsed = protocol.parseTeamMembers(value);
  assert.equal(parsed.members.length, 3);
  const member = protocol.parseTeamMember({
    ...parsed.members[0],
    image: 'https://user:secret@example.invalid/avatar',
    token: 'private',
    password: 'private',
  });
  assert.equal(member.image, undefined);
  assert.equal('token' in member, false);
  assert.equal('password' in member, false);
  assert.throws(
    () => protocol.parseTeamMembers({ members: [member, member], total: 2 }),
    /invalid_response/,
  );
  assert.throws(
    () =>
      protocol.parseTeamState(
        {
          ...teamFixture().state(),
          viewer: { ...member, userId: 'another-account' },
        },
        scope.userId,
      ),
    /invalid_response/,
  );
  delete globalThis.__teamRequest;
});

test('late responses and uncertain writes do not survive page/account/workspace fencing or get replayed', async () => {
  let resolve,
    calls = 0;
  const source = {
    request: async () => {
      calls++;
      return new Promise((next) => {
        resolve = next;
      });
    },
  };
  const session = teamSession(source, scope);
  const pending = session.request({
    operation: 'invite',
    args: { email: 'example@example.invalid', role: 'member' },
  });
  session.close();
  resolve(null);
  await assert.rejects(pending, /scope_changed/);
  await assert.rejects(
    session.request({ operation: 'members', args: { offset: 0 } }),
    /scope_changed/,
  );
  assert.equal(calls, 1);
  await assert.rejects(
    teamFixture().source.request(
      { ...scope, workspaceId: 'another-workspace' },
      { operation: 'state' },
    ),
    /scope_changed/,
  );
});

test('confirmed leave removes only the matching account workspace while retaining other cached data', () => {
  const account = {
    user: { id: 'a', name: 'Alex', email: 'alex@example.invalid' },
    workspaces: [
      { id: 'one', name: 'One', slug: 'one' },
      { id: 'two', name: 'Two', slug: 'two' },
    ],
  };
  assert.equal(
    removeAccountWorkspace(account, 'one', 'another-account'),
    account,
  );
  assert.equal(removeAccountWorkspace(account, 'missing', 'a'), account);
  const updated = removeAccountWorkspace(account, 'one', 'a');
  assert.equal(updated.user, account.user);
  assert.deepEqual(
    updated.workspaces.map((workspace) => workspace.id),
    ['two'],
  );
  assert.equal(account.workspaces.length, 2);
  assert.equal(removeAccountWorkspace(null, 'one', 'a'), null);
  const boot = {
    account,
    initialWorkspace: 'one',
    initialCatalog: { sessions: ['cached-session'] },
  };
  const removed = removeWorkspaceState(boot, 'one', 'a');
  assert.equal(removed.initialWorkspace, '');
  assert.equal(removed.initialCatalog, null);
  const unrelated = removeWorkspaceState(boot, 'two', 'a');
  assert.equal(unrelated.initialCatalog, boot.initialCatalog);
  assert.equal(unrelated.initialWorkspace, 'one');
  const switched = {
    ...boot,
    account: { ...account, user: { ...account.user, id: 'new-account' } },
  };
  assert.equal(removeWorkspaceState(switched, 'one', 'a'), switched);
});

test('invitations, member limits, requests, ownership transfer and leave use explicit operations', async () => {
  const fixture = teamFixture();
  await fixture.source.request(scope, {
    operation: 'invite',
    args: { email: 'new@example.invalid', role: 'admin' },
  });
  let invitations = protocol.parseTeamInvitations(
    await fixture.source.request(scope, { operation: 'invitations' }),
  );
  assert.equal(invitations.at(-1).role, 'admin');
  await fixture.source.request(scope, {
    operation: 'cancelInvitation',
    args: { invitationId: invitations.at(-1).id },
  });
  invitations = protocol.parseTeamInvitations(
    await fixture.source.request(scope, { operation: 'invitations' }),
  );
  assert.equal(invitations.length, 1);
  await assert.rejects(
    fixture.source.request(scope, { operation: 'leave' }),
    /owner_must_transfer/,
  );
  await fixture.source.request(scope, {
    operation: 'reviewRequest',
    args: { requestId: 'pat-request', decision: 'approved' },
  });
  assert.equal(
    protocol.parseTeamOwnerState(
      await fixture.source.request(scope, { operation: 'ownerState' }),
    ).pendingRequests.length,
    0,
  );
  await fixture.source.request(scope, {
    operation: 'transfer',
    args: { memberId: 'casey' },
  });
  assert.equal(fixture.state().viewer.role, 'admin');
  await fixture.source.request(scope, { operation: 'leave' });
  await assert.rejects(
    fixture.source.request(scope, { operation: 'state' }),
    /scope_changed/,
  );
  await assert.rejects(
    teamFixture({ limit: true }).source.request(scope, {
      operation: 'invite',
      args: { email: 'new@example.invalid', role: 'member' },
    }),
    /member_limit/,
  );
  await assert.rejects(
    teamFixture({ role: 'member' }).source.request(scope, {
      operation: 'updateRole',
      args: { memberId: 'casey', role: 'admin' },
    }),
    /permission_denied/,
  );
});

test('invite failure retains existing invitations and role loss updates permissions without another write', async () => {
  const fixture = teamFixture({ rejectOnce: 'invite' });
  await assert.rejects(
    fixture.source.request(scope, {
      operation: 'invite',
      args: { email: 'new@example.invalid', role: 'member' },
    }),
    /unavailable/,
  );
  assert.equal(
    protocol.parseTeamInvitations(
      await fixture.source.request(scope, { operation: 'invitations' }),
    ).length,
    1,
  );
  assert.equal(
    fixture.calls.filter((call) => call.operation === 'invite').length,
    1,
  );
  const lost = teamFixture({ rejectOnce: 'updateRole' });
  await assert.rejects(
    lost.source.request(scope, {
      operation: 'updateRole',
      args: { memberId: 'casey', role: 'admin' },
    }),
    /permission_denied/,
  );
  assert.equal(teamPermissions(lost.state().viewer.role).manage, false);
});

test('official invite and join URLs are checked before accepting links; join and recipient states remain distinct', async () => {
  assert.deepEqual(parseTeamLink('https://lody.ai/invite/invitation_123'), {
    kind: 'invite',
    id: 'invitation_123',
  });
  for (const url of [
    'https://evil.invalid/join/a',
    'https://lody.ai@evil.invalid/join/a',
    'http://lody.ai/join/a',
    'https://lody.ai/join/a?token=private',
    'https://lody.ai/join/a%2Fb',
  ])
    assert.equal(parseTeamLink(url), null);
  const fixture = teamFixture();
  assert.equal(
    protocol.parseTeamInvitePreview(
      await fixture.source.request(entry, {
        operation: 'invitePreview',
        args: { invitationId: 'wrong-recipient' },
      }),
    ).recipientMatchesSession,
    false,
  );
  await fixture.source.request(entry, {
    operation: 'submitRequest',
    args: { token: 'valid', reason: 'Please add me.' },
  });
  assert.equal(
    protocol.parseTeamJoinPreview(
      await fixture.source.request(entry, {
        operation: 'joinPreview',
        args: { token: 'valid' },
      }),
    ).viewer.request.status,
    'pending',
  );
});
