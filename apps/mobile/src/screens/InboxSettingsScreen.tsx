import { NativeGroupedList } from '@lody-ios/kit';
import { useConnection } from '@/cloud/catalog/connection';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePalette } from '@/theme/palette';
import { definePage, usePageRuntime } from '@/presentation';
import { currentLocale, t } from '../i18n/index.ts';

function View() {
  const { params, finish } = usePageRuntime<{ mode: number }, number>();
  const colors = usePalette();
  const connection = useConnection();
  const { refresh } = useCatalog();
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      transparent
      accent={colors.accent}
      sections={[
        {
          id: 'view',
          header: t('inbox.settings.section.view'),
          rows: (
            [
              'inbox.settings.view.projects',
              'inbox.settings.view.activity',
            ] as const
          ).map((key, index) => ({
            id: String(index),
            title: t(key),
            image: params.mode === index ? 'checkmark' : undefined,
            action: true,
          })),
        },
        {
          id: 'sync',
          header: t('inbox.settings.section.sync'),
          rows: [
            {
              id: 'sync',
              title: t(
                (
                  {
                    offline: 'inbox.settings.sync.offline',
                    syncing: 'inbox.settings.sync.syncing',
                    live: 'inbox.settings.sync.live',
                  } as const
                )[connection.state],
              ),
              subtitle: connection.syncedAt
                ? t('inbox.settings.sync.lastSynced', {
                    time: new Date(connection.syncedAt).toLocaleString(
                      currentLocale(),
                    ),
                  })
                : undefined,
              image: 'arrow.clockwise',
              action: true,
            },
          ],
        },
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'sync') refresh();
        else if (id === '0' || id === '1') finish(Number(id));
      }}
    />
  );
}

export const InboxSettingsScreen = definePage<{ mode: number }, number>({
  id: 'inbox-settings',
  title: t('inbox.settings.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('请从首页打开');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [0.5, 1],
    sheetGrabberVisible: true,
  },
});
