import { useEffect, useState } from 'react';
import {
  NativeGroupedList,
  listDir,
  previewContent,
  readFile,
  showToast,
  type DirectoryEntry,
  type NativeListSection,
} from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { usePalette } from '@/theme/palette';
import { filePage } from './filePage';
import { t, type TranslationKey } from '../../../i18n/index.ts';

export type FilesParams = {
  workspaceId: string;
  sessionId: string;
  userId: string;
  path: string;
  title: string;
};

const join = (base: string, name: string) => (base ? `${base}/${name}` : name);

const READ_ERRORS: Record<string, TranslationKey> = {
  too_large: 'files.error.tooLarge',
  file_not_found: 'files.error.notFound',
  permission_denied: 'files.error.permissionDenied',
  path_not_allowed: 'files.error.pathNotAllowed',
  decode_error: 'files.error.decode',
};

function FilesScreen() {
  const { params, push } = usePageRuntime<FilesParams>();
  const colors = usePalette();
  const [entries, setEntries] = useState<DirectoryEntry[]>();
  const [truncated, setTruncated] = useState(false);
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  const [opening, setOpening] = useState('');

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
        filesPage,
        { ...params, path, title: entry.name },
        { title: entry.name },
      );
      return;
    }
    if (opening) return;
    setOpening(path);
    try {
      const file = await readFile({ sessionId: params.sessionId, path });
      if (file.status !== 'ok') {
        const key = READ_ERRORS[file.code];
        showToast(key ? t(key) : (file.message ?? t('files.error.read')));
        return;
      }
      if (file.kind === 'image' || file.kind === 'binary')
        await previewContent(file.handle);
      else
        void push(
          filePage,
          { path, handle: file.handle, bytes: file.bytes },
          { title: entry.name },
        );
    } catch {
      showToast(t('files.error.offline'));
    } finally {
      setOpening('');
    }
  };

  const sections: NativeListSection[] = [
    {
      id: 'entries',
      footer: error || (truncated ? t('files.truncated') : undefined),
      rows: [
        ...(entries ?? []).map((entry) => ({
          id: `entry:${entry.name}`,
          title: entry.name,
          image: entry.type === 'directory' ? 'folder' : 'doc.text',
          imageTint: entry.type === 'directory' ? undefined : 'secondary',
          action: true,
          navigates: entry.type === 'directory',
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

export const filesPage = definePage<FilesParams>({
  id: 'files',
  title: t('files.title'),
  Component: FilesScreen,
  parseRouteParams: () => {
    throw new Error('请从会话打开');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
