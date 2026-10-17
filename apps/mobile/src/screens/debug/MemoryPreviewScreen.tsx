import { useCallback, useEffect, useRef } from 'react';
import type { MemorySnapshot } from '@lody/cloud-runtime/models/memory';
import type { MemoryService } from '@/cloud/memory';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { definePage } from '@/lib/presentation';
import { NativeGroupedList } from '@lody-ios/kit';
import { MemorySettingsView } from '../MemorySettingsScreen';
import { switchSettingsBaselineAccount } from './settingsBaseline';

type State = MemorySnapshot['status'] | 'cached' | 'empty' | 'catalog_denied';
function View({ state }: { state?: State }) {
  const { account } = useAuth();
  const cleanup = useRef<(() => void) | null>(null);
  useEffect(() => () => cleanup.current?.(), []);
  const entries = useRef<MemorySnapshot['entries']>([
    {
      machineId: 'studio',
      providerId: 'nowledge-mem',
      memoryId: 'review',
      name: 'Reviewer',
      description: 'Code review preferences',
    },
    {
      machineId: 'studio',
      providerId: 'nowledge-mem',
      memoryId: 'deleted',
      name: 'Previous identity',
    },
  ]);
  const fail = useRef(true),
    failRemove = useRef(true),
    failImport = useRef(true);
  const service = useCallback<MemoryService>(
    async (request) => {
      if (state === 'catalog_denied') throw new Error('memory_forbidden');
      if (!state && request.action === 'list' && fail.current) {
        fail.current = false;
        throw new Error('offline');
      }
      const machineId = request.machineId ?? state ?? 'studio';
      if (request.action === 'import') {
        if (request.memoryId === 'new' && failImport.current) {
          failImport.current = false;
          throw new Error('memory_not_running');
        }
        if (request.memoryId === 'switch') {
          cleanup.current = switchSettingsBaselineAccount();
          return new Promise<MemorySnapshot>(() => {});
        }
        entries.current.push({
          machineId,
          providerId: 'nowledge-mem',
          memoryId: request.memoryId,
          name: 'Reviewer',
          description: 'Imported from provider',
        });
      }
      if (request.action === 'remove') {
        if (request.base.memoryId === 'new') {
          cleanup.current = switchSettingsBaselineAccount();
          return new Promise<MemorySnapshot>(() => {});
        }
        entries.current = entries.current.filter(
          (e) => e.memoryId !== request.base.memoryId,
        );
        if (failRemove.current) {
          failRemove.current = false;
          throw new Error('memory_write_unknown');
        }
      }
      let machines = [
        { id: 'studio', name: 'Studio' },
        { id: 'laptop', name: 'Laptop' },
      ];
      const statuses = [
        'not_installed',
        'not_running',
        'unsupported',
        'error',
        'forbidden',
        'unknown',
        'cached',
        'empty',
      ] as const;
      if (state) machines = [{ id: state, name: 'Studio' }];
      let status: MemorySnapshot['status'] = 'ready';
      if (machineId === 'laptop') status = 'offline';
      if (
        statuses.some((s) => s === machineId) &&
        machineId !== 'cached' &&
        machineId !== 'empty'
      )
        status = machineId as MemorySnapshot['status'];
      const result: MemorySnapshot = {
        machines,
        machineId,
        status,
        cached: machineId === 'cached',
        entries: machineId === 'studio' ? structuredClone(entries.current) : [],
        identities:
          status === 'ready' && machineId !== 'empty'
            ? [
                {
                  id: 'review',
                  name: 'Reviewer',
                  description: 'Code review preferences',
                },
                {
                  id: 'new',
                  name: 'Reviewer',
                  description: 'Another identity with the same name',
                },
                { id: 'switch', name: 'Switch account' },
              ]
            : [],
      };
      if (machineId === 'laptop' || machineId === 'cached')
        result.entries = [
          {
            machineId,
            providerId: 'nowledge-mem',
            memoryId: 'review',
            name: 'Reviewer',
            description: 'A different computer’s identity',
          },
        ];
      if (machineId === 'unsupported')
        result.entries = [
          {
            machineId,
            providerId: 'future-provider',
            memoryId: 'future',
            name: 'Other provider',
          },
        ];
      return result;
    },
    [state],
  );
  if (cleanup.current && account?.user.id === 'settings-baseline-user')
    return (
      <NativeGroupedList
        style={{ flex: 1 }}
        onRowPress={() => {}}
        sections={[
          {
            id: 'scope',
            rows: [
              { id: 'memory-scope-switched', title: 'Memory account switched' },
            ],
          },
        ]}
      />
    );
  return <MemorySettingsView workspaceId="offline-memory" service={service} />;
}
export const MemoryPreviewScreen = definePage({
  id: 'memory-preview',
  title: 'Memory',
  Component: View,
  presentation: { headerVariant: 'transparent' },
});
export const MemoryStatesPreviewScreen = definePage({
  id: 'memory-states-preview',
  title: 'Memory States',
  Component: () => <View state="not_installed" />,
  presentation: { headerVariant: 'transparent' },
});

export const memoryStatePages = (
  [
    'catalog_denied',
    'not_installed',
    'not_running',
    'unsupported',
    'error',
    'forbidden',
    'unknown',
    'cached',
    'empty',
  ] as const
).map((state) =>
  definePage({
    id: `memory-state-${state}`,
    title: 'Memory States',
    Component: () => <View state={state} />,
    presentation: { headerVariant: 'transparent' },
  }),
);
