import type { SavedAccount } from '../../models/auth.ts';

export function removeAccountWorkspace<T extends SavedAccount>(
  account: T | null,
  workspaceId: string,
  expectedUserId: string,
): T | null {
  if (
    !account ||
    account.user.id !== expectedUserId ||
    !workspaceId ||
    !account.workspaces.some((workspace) => workspace.id === workspaceId)
  )
    return account;
  return {
    ...account,
    workspaces: account.workspaces.filter(
      (workspace) => workspace.id !== workspaceId,
    ),
  };
}

export function removeWorkspaceState<
  T extends {
    account: SavedAccount | null;
    initialWorkspace: string;
    initialCatalog: unknown;
  },
>(state: T, workspaceId: string, expectedUserId: string): T {
  const account = removeAccountWorkspace(
    state.account,
    workspaceId,
    expectedUserId,
  );
  if (account === state.account) return state;
  const removedInitial = state.initialWorkspace === workspaceId;
  return {
    ...state,
    account,
    initialWorkspace: removedInitial ? '' : state.initialWorkspace,
    initialCatalog: removedInitial ? null : state.initialCatalog,
  };
}
