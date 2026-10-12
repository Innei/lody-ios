import { NativeGroupedList } from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { useComposerRunOptions } from '@/hooks/screens/useComposerRunOptions';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { roleOptionSummary } from '@/features/sessions/runOptions';
import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';
import type {
  AgentRoleOption,
  RunOptionsCatalog,
} from '@lody/cloud-runtime/models/run-options';

type Params = { role?: AgentRoleOption; fixture?: RunOptionsCatalog };

function View() {
  const { params, present } = usePageRuntime<Params>();
  const { account } = useAuth();
  const { selected, catalog } = useCatalog();
  const options = useComposerRunOptions(
    account && selected && !params.role
      ? {
          workspaceId: selected.id,
          userId: account.user.id,
        }
      : undefined,
    params.fixture,
  );
  const role = params.role;
  if (role) {
    const values = role.runConfig;
    const unavailable = t(
      `runOptions.roles.${role.unavailableReason ?? 'unavailable'}`,
    );
    return (
      <NativeGroupedList
        style={{ flex: 1 }}
        sections={[
          {
            id: 'role',
            footer: t('runOptions.roles.desktopHint'),
            rows: [
              {
                id: 'name',
                title: role.name,
                subtitle: role.description,
                action: false,
              },
              {
                id: 'agent',
                title: t('create.label.agent'),
                value: role.agentName,
                action: false,
              },
              {
                id: 'machine',
                title: t('create.label.machine'),
                value: catalog.machineNames?.[role.machineId] ?? role.machineId,
                action: false,
              },
              ...(values.modelId
                ? [
                    {
                      id: 'model',
                      title: t('create.label.model'),
                      value: values.modelId,
                      action: false,
                    },
                  ]
                : []),
              ...(values.modeId
                ? [
                    {
                      id: 'mode',
                      title: t('runOptions.roles.permission'),
                      value: values.modeId,
                      action: false,
                    },
                  ]
                : []),
              ...Object.entries(values.configOptionValues ?? {}).map(
                ([id, value]) => ({
                  id: `option:${id}`,
                  title: id,
                  value: String(value),
                  action: false,
                }),
              ),
              {
                id: 'revision',
                title: t('runOptions.roles.revision'),
                value: String(role.revision),
                action: false,
              },
              ...(!role.available
                ? [
                    {
                      id: 'unavailable',
                      title: unavailable,
                      action: false,
                    },
                  ]
                : []),
            ],
          },
        ]}
        onRowPress={() => {}}
      />
    );
  }
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      refreshing={options.loading}
      onRefresh={options.refresh}
      placeholder={t(
        options.loading ? 'common.reading' : 'runOptions.roles.empty',
      )}
      sections={[
        {
          id: 'roles',
          footer: t('runOptions.roles.desktopHint'),
          rows: options.catalog.roles.map((role) => ({
            id: role.id,
            title: role.name,
            subtitle: [
              roleOptionSummary(role),
              role.available
                ? ''
                : t(
                    `runOptions.roles.${role.unavailableReason ?? 'unavailable'}`,
                  ),
            ]
              .filter(Boolean)
              .join('\n'),
            wrapSubtitle: true,
            action: true,
            disclosure: true,
            navigates: true,
          })),
        },
        ...(options.error
          ? [
              {
                id: 'error',
                rows: [
                  {
                    id: 'retry',
                    title: t('runOptions.unavailable'),
                    image: 'arrow.clockwise',
                    action: true,
                  },
                ],
              },
            ]
          : []),
      ]}
      onRowPress={({ nativeEvent }) => {
        if (nativeEvent.id === 'retry') {
          options.refresh();
          return;
        }
        const role = options.catalog.roles.find(
          (item) => item.id === nativeEvent.id,
        );
        if (role)
          void present(AgentRolesScreen, { role }, { title: role.name });
      }}
    />
  );
}

export const AgentRolesScreen = definePage<Params>({
  id: 'agent-roles',
  title: t('runOptions.roles.title'),
  Component: View,
  parseRouteParams: () => ({}),
  presentation: { style: 'push', headerVariant: 'transparent' },
});
