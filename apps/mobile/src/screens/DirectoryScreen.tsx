import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, PlatformColor } from 'react-native';
import {
  NativeGroupedList,
  localProjects,
  type NativeListSection,
} from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { useSheetHeader } from '@/presentation/SheetStack';
import type { Project } from '@/models/catalog';
import type { Directory } from '../../modules/lody-kit/data-runtime/local-projects';
import { usePalette } from '@/theme/palette';
import { t } from '../i18n/index.ts';

type Machine = { id: string; name: string };
type Params = {
  workspaceId: string;
  browserId: string;
  machine?: Machine;
  path?: string;
  select?: (project: Project) => void;
};

function directoryFooter(error: string, saving: boolean, loading: boolean) {
  if (error) return error;
  if (saving) return t('directory.saving');
  if (loading) return t('directory.loading');
}

function directoryPlaceholder(loading: boolean, hasMachine: boolean) {
  if (loading) return t('common.reading');
  if (hasMachine) return t('directory.empty');
  return t('directory.noMachine');
}

function View() {
  const { params, finish, push } = usePageRuntime<Params, Project>();
  const colors = usePalette();
  const [machine, setMachine] = useState(params.machine);
  const [machines, setMachines] = useState<Machine[]>([]);
  const [directory, setDirectory] = useState<Directory>();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  const mounted = useRef(true);
  const busy = useRef(false);
  const select = params.select ?? finish;
  const request = useCallback(
    async (action: string, extra: object = {}) =>
      JSON.parse(
        await localProjects(
          JSON.stringify({
            workspaceId: params.workspaceId,
            browserId: params.browserId,
            machineId: machine?.id,
            action,
            ...extra,
          }),
        ),
      ),
    [params.workspaceId, params.browserId, machine?.id],
  );

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      if (!params.select)
        void localProjects(
          JSON.stringify({ ...params, action: 'cancel' }),
        ).catch(() => {});
    };
  }, [params]);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError('');
    void (async () => {
      try {
        if (!machine) {
          const value = await request('machines');
          if (!active) return;
          setMachines(value.machines);
          if (value.machines.length === 1) setMachine(value.machines[0]);
        } else {
          const value = await request('browse', { path: params.path });
          if (active) setDirectory(value);
        }
      } catch {
        if (active)
          setError(
            machine ? t('directory.error.read') : t('directory.error.machines'),
          );
      } finally {
        if (active) setLoading(false);
      }
    })();
    return () => {
      active = false;
    };
  }, [machine, params.path, request, revision]);

  const enter = useCallback(
    (path: string) => {
      if (!machine || busy.current) return;
      void push(
        DirectoryScreen,
        { ...params, machine, path, select },
        { title: path.split(/[\\/]/).filter(Boolean).at(-1) || path },
      );
    },
    [machine, params, push, select],
  );

  const confirm = useCallback(async () => {
    if (!directory || loading || busy.current) return;
    busy.current = true;
    setSaving(true);
    setError('');
    try {
      const project: Project = await request('add', { path: directory.path });
      if (mounted.current) select(project);
    } catch (cause) {
      if (mounted.current)
        setError(
          String(cause).includes('project_write_unknown')
            ? t('directory.error.registerUnknown')
            : t('directory.error.register'),
        );
    } finally {
      busy.current = false;
      if (mounted.current) setSaving(false);
    }
  }, [directory, loading, request, select]);

  const items = useMemo(
    () =>
      machine
        ? [
            {
              type: 'button' as const,
              variant: 'prominent' as const,
              tintColor: PlatformColor('systemBlue'),
              icon: { type: 'sfSymbol' as const, name: 'checkmark' },
              accessibilityLabel: t(
                saving
                  ? 'directory.accessibility.using'
                  : 'directory.accessibility.use',
              ),
              disabled: !directory || loading || saving,
              onPress: () => void confirm(),
            },
          ]
        : [],
    [machine, directory, loading, saving, confirm],
  );
  useSheetHeader(items);

  const sections: NativeListSection[] = machine
    ? [
        {
          id: 'location',
          header: machine.name,
          footer: directoryFooter(error, saving, loading),
          rows: [
            {
              id: 'path',
              title: directory?.path ?? params.path ?? t('directory.home'),
              subtitle: t('directory.enterPath'),
              subtitleMono: true,
              action: !saving,
              image: 'folder',
            },
            ...(error
              ? [{ id: 'retry', title: t('common.retry'), action: !saving }]
              : []),
          ],
        },
        {
          id: 'directories',
          rows: (directory?.entries ?? []).map((entry, i) => ({
            id: `entry:${i}`,
            title: entry.name,
            image: 'folder',
            subtitle: entry.error ? t('directory.entry.noAccess') : undefined,
            action: !entry.error && !saving,
            navigates: true,
            disclosure: true,
          })),
        },
        ...(directory?.truncated
          ? [
              {
                id: 'more',
                rows: [
                  {
                    id: 'more',
                    title: t(loading ? 'common.reading' : 'common.loadMore'),
                    action: !loading && !saving,
                  },
                ],
              },
            ]
          : []),
      ]
    : [
        {
          id: 'machines',
          footer: error,
          rows: [
            ...machines.map((m) => ({
              id: m.id,
              title: m.name,
              image: 'desktopcomputer',
              action: true,
              navigates: true,
              disclosure: true,
            })),
            ...(error
              ? [{ id: 'retry', title: t('common.retry'), action: true }]
              : []),
          ],
        },
      ];

  async function more() {
    if (loading || !directory?.nextCursor) return;
    setLoading(true);
    try {
      const next: Directory = await request('browse', {
        path: directory.path,
        cursor: directory.nextCursor,
      });
      if (mounted.current)
        setDirectory({
          ...next,
          entries: [
            ...directory.entries,
            ...next.entries.filter(
              (e) =>
                !directory.entries.some(
                  (old) => old.absolutePath === e.absolutePath,
                ),
            ),
          ],
        });
    } catch {
      if (mounted.current) setError(t('directory.error.loadMore'));
    } finally {
      if (mounted.current) setLoading(false);
    }
  }

  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      transparent
      accent={colors.accent}
      sections={sections}
      placeholder={directoryPlaceholder(loading, !!machine)}
      onRowPress={({ nativeEvent: { id } }) => {
        if (busy.current) return;
        if (id === 'retry') {
          setRevision((n) => n + 1);
          return;
        }
        if (!machine) {
          const picked = machines.find((m) => m.id === id);
          if (picked)
            void push(
              DirectoryScreen,
              { ...params, machine: picked, select },
              { title: picked.name },
            );
        } else if (id === 'path') {
          Alert.prompt(
            t('directory.prompt.title'),
            t('directory.prompt.message'),
            [
              { text: t('common.cancel'), style: 'cancel' },
              {
                text: t('common.open'),
                onPress: (path?: string) => {
                  if (path?.trim()) enter(path.trim());
                },
              },
            ],
            'plain-text',
            directory?.path ?? '',
            'default',
          );
        } else if (id === 'more') void more();
        else {
          const entry = directory?.entries[Number(id.slice(6))];
          if (entry && !entry.error) enter(entry.absolutePath);
        }
      }}
    />
  );
}

export const DirectoryScreen = definePage<Params, Project>({
  id: 'directory',
  title: t('directory.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('请从选择项目打开');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
    sheetGrabberVisible: true,
  },
});
