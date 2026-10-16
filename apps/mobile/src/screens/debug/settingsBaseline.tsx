import { useSyncExternalStore, type PropsWithChildren } from 'react';
import { View } from 'react-native';
import { AuthContext, useAuth } from '@/cloud/auth/AuthProvider';
import { CatalogContext, useCatalog } from '@/cloud/catalog/CatalogProvider';
import { getConnection, publishConnection } from '@/cloud/catalog/connection';
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
type Fixture = { scenario: Scenario; refreshes: number; startedAt: number };
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

export async function openSettingsBaseline(scenario: Scenario) {
  if (!uiVerify) return;
  const previous = getConnection();
  const current = { scenario, refreshes: 0, startedAt: Date.now() };
  update(current);
  const hasCatalog = scenario === 'cached' || scenario === 'live';
  let state: 'live' | 'syncing' | 'offline' = 'offline';
  if (scenario === 'live') state = 'live';
  if (scenario === 'syncing') state = 'syncing';
  publishConnection({
    state,
    machines: hasCatalog ? cached.machineIds.length : 0,
    syncedAt: hasCatalog ? current.startedAt - 60_000 : undefined,
  });
  try {
    await present(SettingsScreen, {});
  } finally {
    if (fixture?.startedAt === current.startedAt) {
      update(null);
      publishConnection(previous);
    }
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
        token: '',
        user: {
          id: 'settings-baseline-user',
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
        update({ ...current, scenario: 'signed-out' });
        publishConnection({ state: 'offline', machines: 0 });
      },
    };
    catalogValue = {
      ...catalog,
      catalog: hasCatalog ? cached : empty,
      serverSessions: [],
      selected: hasWorkspace ? workspace : undefined,
      loading: scenario === 'syncing',
      connected: scenario === 'live' || scenario === 'syncing',
      syncedAt: getConnection().syncedAt,
      key: hasWorkspace ? workspace.id : '',
      refresh: () => {
        update({
          ...current,
          scenario: 'syncing',
          refreshes: current.refreshes + 1,
        });
        publishConnection({ ...getConnection(), state: 'syncing' });
      },
    };
  }
  return (
    <AuthContext value={authValue}>
      <CatalogContext value={catalogValue}>
        {children}
        {current && (
          <View
            accessible
            testID="settings-baseline-ready"
            accessibilityLabel={`${scenario}:refreshes=${current.refreshes}`}
            style={{ position: 'absolute', width: 1, height: 1 }}
          />
        )}
      </CatalogContext>
    </AuthContext>
  );
}
