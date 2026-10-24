import { useSyncExternalStore, type PropsWithChildren } from 'react';
import { View } from 'react-native';
import { AuthContext, useAuth } from '@/cloud/auth/AuthProvider';
import { CatalogContext, useCatalog } from '@/cloud/catalog/CatalogProvider';
import {
  ConnectionContext,
  getConnection,
  type Connection,
} from '@/cloud/catalog/connection';
import { present } from '@/lib/presentation';
import { SettingsScreen } from '../SettingsScreen';
import { uiVerify } from './uiVerify';

export const settingsBaselineScenarios = [
  'signed-out',
  'no-workspace',
  'live',
  'syncing',
  'offline',
  'cached',
] as const;
type Scenario = (typeof settingsBaselineScenarios)[number];
type Fixture = {
  scenario: Scenario;
  refreshes: number;
  startedAt: number;
  connection?: Connection;
  userId?: string;
};
let fixture: Fixture | null = null;
const listeners = new Set<() => void>();
const workspace = {
  id: 'settings-baseline',
  name: 'Baseline Workspace',
  slug: null,
};
const empty = { projects: [], sessions: [], machineIds: [] };
const cached = { ...empty, machineIds: ['baseline-mac', 'baseline-laptop'] };

function update(next: Fixture | null) {
  fixture = next;
  for (const listener of listeners) listener();
}

export function switchSettingsBaselineAccount(
  userId = 'settings-baseline-user',
) {
  if (!uiVerify) return () => {};
  const previous = fixture;
  const current: Fixture = {
    scenario: 'live',
    userId,
    refreshes: 0,
    startedAt: Date.now(),
  };
  update(current);
  return () => {
    if (fixture === current) update(previous);
  };
}

export async function openSettingsBaseline(scenario: Scenario) {
  if (!uiVerify) return;
  const startedAt = Date.now();
  const hasCatalog = scenario === 'cached' || scenario === 'live';
  let state: Connection['state'] = 'offline';
  if (scenario === 'live') state = 'live';
  if (scenario === 'syncing') state = 'syncing';
  update({
    scenario,
    refreshes: 0,
    startedAt,
    connection: {
      state,
      machines: hasCatalog ? cached.machineIds.length : 0,
      syncedAt: hasCatalog ? startedAt - 60_000 : undefined,
    },
  });
  try {
    await present(SettingsScreen, {});
  } finally {
    if (fixture?.startedAt === startedAt) update(null);
  }
}

export function SettingsBaselineProviders({ children }: PropsWithChildren) {
  const auth = useAuth();
  const catalog = useCatalog();
  const current = useSyncExternalStore(
    (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    () => fixture,
  );
  const scenario = current?.scenario;
  const signedIn = scenario !== 'signed-out';
  const hasWorkspace = signedIn && scenario !== 'no-workspace';
  const hasCatalog = scenario === 'cached' || scenario === 'live';
  let authValue = auth;
  let catalogValue = catalog;
  if (current) {
    let account: typeof auth.account = null;
    if (signedIn) {
      account = {
        user: {
          id: current.userId ?? 'settings-baseline-user',
          name: 'Settings Preview',
          email: 'baseline@example.test',
        },
        workspaces: hasWorkspace ? [workspace] : [],
      };
    }
    authValue = {
      ...auth,
      account,
      logout: async () => {
        update({
          ...current,
          scenario: 'signed-out',
          connection: { state: 'offline', machines: 0 },
        });
      },
    };
    catalogValue = {
      ...catalog,
      catalog: hasCatalog ? cached : empty,
      serverSessions: [],
      selected: hasWorkspace ? workspace : undefined,
      loading: scenario === 'syncing',
      connected: scenario === 'live' || scenario === 'syncing',
      syncedAt: (current.connection ?? getConnection()).syncedAt,
      key: hasWorkspace ? workspace.id : '',
      refresh: () => {
        update({
          ...current,
          scenario: 'syncing',
          refreshes: current.refreshes + 1,
          connection: {
            ...(current.connection ?? getConnection()),
            state: 'syncing',
          },
        });
      },
    };
  }
  return (
    <AuthContext value={authValue}>
      <CatalogContext value={catalogValue}>
        <ConnectionContext value={current?.connection ?? null}>
          {children}
          {current && (
            <View
              accessible
              testID="settings-baseline-ready"
              accessibilityLabel={`${scenario}:refreshes=${current.refreshes}`}
              style={{ position: 'absolute', width: 1, height: 1 }}
            />
          )}
        </ConnectionContext>
      </CatalogContext>
    </AuthContext>
  );
}
