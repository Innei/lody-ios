import { useCallback, useRef } from 'react';
import type { RemoteSetting } from '@lody/cloud-runtime/models/settings';
import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';
import {
  RemoteSettingsView,
  type SettingsService,
} from '../RemoteSettingsScreen';

function View() {
  const rows = useRef<RemoteSetting[]>([
    {
      kind: 'mcp',
      id: 'docs',
      name: 'Documentation',
      detail: 'http',
      configured: true,
      enabledByDefault: false,
      updatedAt: 1,
    },
    {
      kind: 'mcp',
      id: 'search',
      name: 'Search',
      detail: 'stdio',
      configured: true,
      enabledByDefault: false,
      updatedAt: 1,
    },
    {
      kind: 'mcp',
      id: 'missing',
      name: 'Needs setup',
      detail: 'http',
      configured: false,
      enabledByDefault: false,
      updatedAt: 1,
    },
    {
      kind: 'mcp',
      id: 'readonly',
      name: 'Read only',
      detail: 'stdio',
      configured: true,
      readOnly: true,
    },
  ]);
  const failSave = useRef(true);
  const failDelete = useRef(true);
  const service = useCallback<SettingsService>(async ({ edit, remove }) => {
    if (edit) {
      if (
        rows.current.some(
          (row) =>
            row.id !== edit.item.id &&
            row.name.toLowerCase() === edit.name.trim().toLowerCase(),
        )
      )
        throw new Error(t('settings.remote.duplicate'));
      if (failSave.current) {
        failSave.current = false;
        throw new Error(t('settings.remote.saveFailed'));
      }
      rows.current = rows.current.map((row) =>
        row.id === edit.item.id
          ? {
              ...row,
              name: edit.name.trim(),
              enabledByDefault: edit.enabledByDefault,
              updatedAt: 2,
            }
          : row,
      );
    }
    if (remove) {
      if (failDelete.current) {
        failDelete.current = false;
        throw new Error(t('settings.remote.conflict'));
      }
      rows.current = rows.current.filter((row) => row.id !== remove.id);
    }
    return rows.current;
  }, []);
  return (
    <RemoteSettingsView
      workspaceId="offline-mcp"
      kind="mcp"
      service={service}
    />
  );
}

export const McpSettingsPreviewScreen = definePage({
  id: 'mcp-settings-preview',
  title: 'MCP',
  Component: View,
  presentation: { headerVariant: 'transparent' },
});
