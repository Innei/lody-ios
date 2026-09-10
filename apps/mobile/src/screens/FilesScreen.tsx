import { useEffect, useState } from 'react';
import {
  NativeGroupedList,
  listDir,
  type DirectoryEntry,
  type NativeListSection,
} from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { useOpenFile } from '@/hooks/screens/useOpenFile';
import { t } from '../lib/i18n/index.ts';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

export type FilesParams = {
  workspaceId: string;
  sessionId: string;
  userId: string;
  path: string;
  title: string;
};

const join = (base: string, name: string) => (base ? `${base}/${name}` : name);

function View() {
  const { params, push } = usePageRuntime<FilesParams>();
  const colors = usePalette();
  const [entries, setEntries] = useState<DirectoryEntry[]>();
  const [truncated, setTruncated] = useState(false);
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  const openFile = useOpenFile(params.sessionId);

  useEffect(() => {
    let active = true;
    setError('');
    listDir({
      workspaceId: params.workspaceId,
      sessionId: params.sessionId,
      relativePath: params.path,
      userId: params.userId,
    })
      .then((listing) => {
        if (!active) return;
        setEntries(listing.entries);
        setTruncated(listing.truncated);
      })
      .catch((cause: Error) => {
        if (active)
          setError(
            /permission_denied/.test(String(cause))
              ? t('files.error.archived')
              : t('files.error.directory'),
          );
      });
    return () => {
      active = false;
    };
  }, [params.workspaceId, params.sessionId, params.path, revision]);

  const open = async (entry: DirectoryEntry) => {
    const path = join(params.path, entry.name);
    if (entry.type === 'directory') {
      void push(
        FilesScreen,
        { ...params, path, title: entry.name },
        { title: entry.name },
      );
      return;
    }
    await openFile(path);
  };

  const sections: NativeListSection[] = [
    {
      id: 'entries',
      footer: error || (truncated ? t('files.truncated') : undefined),
      rows: [
        ...(entries ?? []).map((entry) => ({
          id: `entry:${entry.name}`,
          title: entry.name,
          image: entry.type === 'directory' ? 'folder' : undefined,
          filePath:
            entry.type === 'file' ? join(params.path, entry.name) : undefined,
          imageTint: entry.type === 'directory' ? undefined : 'secondary',
          action: true,
          navigates: true,
          disclosure: entry.type === 'directory',
        })),
        ...(error
          ? [{ id: 'retry', title: t('common.retry'), action: true }]
          : []),
      ],
    },
  ];

  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={sections}
      placeholder={t(entries ? 'files.emptyFolder' : 'common.reading')}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'retry') {
          setRevision((n) => n + 1);
          return;
        }
        const entry = entries?.find((item) => `entry:${item.name}` === id);
        if (entry) void open(entry);
      }}
    />
  );
}

export const FilesScreen = definePage<FilesParams>({
  id: 'files',
  title: t('files.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from a session');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
