import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  NativeGroupedList,
  NativeNavigationHeader,
  type NativeListSection,
} from '@lody-ios/kit';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { requestProvider } from '@/cloud/providers';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import {
  providerError,
  providerStatus,
  providerTypeLabel,
} from '@/features/providers/provider-config';
import type {
  ProviderMachine,
  ProviderService,
  ProviderSummary,
} from '@lody/cloud-runtime/models/providers';
import { t } from '@/lib/i18n';
import { ProviderEditorScreen } from './ProviderEditorScreen';
import {
  ProviderChoiceScreen,
  providerChoiceType,
} from './ProviderChoiceScreen';

export function ProviderManagementView({
  workspaceId,
  service = requestProvider,
}: {
  workspaceId: string;
  service?: ProviderService;
}) {
  const { present } = usePageRuntime();
  const [machines, setMachines] = useState<ProviderMachine[]>([]);
  const [providers, setProviders] = useState<ProviderSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const generation = useRef(0);
  const load = useCallback(
    async (visible = true) => {
      const id = ++generation.current;
      if (visible) setLoading(true);
      try {
        const result = await service({ action: 'list', workspaceId });
        if (generation.current !== id) return;
        setMachines(result.machines ?? []);
        setProviders(result.providers ?? []);
        setError('');
      } catch (cause) {
        if (generation.current === id) setError(providerError(cause));
      } finally {
        if (generation.current === id) setLoading(false);
      }
    },
    [service, workspaceId],
  );
  useEffect(() => {
    void load();
    return () => {
      generation.current++;
    };
  }, [load]);
  useEffect(() => {
    if (!providers.some((provider) => provider.state !== 'configured')) return;
    const interval = setInterval(() => void load(false), 3000);
    return () => clearInterval(interval);
  }, [providers, load]);
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'arrow.clockwise' },
        accessibilityLabel: t('providers.refresh'),
        disabled: loading,
        onPress: () => void load(),
      },
    ],
    [loading, load],
  );
  const sections: NativeListSection[] = machines.map((machine) => {
    const items = providers.filter(
      (provider) => provider.machineId === machine.id,
    );
    let footer = t('providers.online');
    if (machine.readOnly) footer = t('providers.readOnly');
    else if (machine.availability !== 'online')
      footer = t(`providers.${machine.availability}`);
    return {
      id: `provider-machine:${machine.id}`,
      header: machine.name,
      footer,
      rows: [
        ...items.map((provider) => ({
          id: `provider:${machine.id}:${provider.id}`,
          title: provider.name,
          subtitle: `${providerTypeLabel(provider)} · ${
            provider.overLimit
              ? t('providers.manageOnDesktop')
              : providerStatus(provider.state)
          }`,
          disclosure: !machine.readOnly,
          action: !machine.readOnly,
          navigates: !machine.readOnly,
        })),
        {
          id: `provider-add:${machine.id}`,
          title: t('providers.add'),
          image: 'plus',
          imageTint: 'blue',
          action: !machine.readOnly,
          disclosure: !machine.readOnly,
        },
      ],
    };
  });
  if (error)
    sections.unshift({
      id: 'provider-error',
      header: '',
      footer: error,
      rows: [
        {
          id: 'provider-retry',
          title: t('providers.retry'),
          image: 'arrow.clockwise',
          imageTint: 'blue',
          action: true,
          disclosure: false,
        },
      ],
    });
  return (
    <>
      <NativeNavigationHeader title={t('providers.title')} items={actions} />
      <NativeGroupedList
        style={{ flex: 1 }}
        refreshing={loading}
        onRefresh={() => void load()}
        placeholder={loading ? t('providers.loading') : t('providers.empty')}
        sections={sections}
        onRowPress={({ nativeEvent: { id } }) => {
          if (id === 'provider-retry') {
            void load();
            return;
          }
          const machine = machines.find(
            (machine) =>
              id === `provider-add:${machine.id}` ||
              id.startsWith(`provider:${machine.id}:`),
          );
          if (!machine || machine.readOnly) return;
          const scope = { workspaceId, machine, service };
          if (id.startsWith('provider-add:')) {
            void present(ProviderChoiceScreen, {}).then(async (result) => {
              if (result.status !== 'completed') return;
              try {
                const cliType = providerChoiceType(result.value);
                const reply = await service({
                  action: 'draft',
                  workspaceId,
                  machineId: machine.id,
                  cliType,
                  agentType: result.value,
                });
                if (!reply.config) throw new Error('invalid_provider_response');
                await present(ProviderEditorScreen, {
                  ...scope,
                  draft: reply.config,
                });
                void load();
              } catch (cause) {
                setError(providerError(cause));
              }
            });
            return;
          }
          const provider = providers.find(
            (provider) => id === `provider:${machine.id}:${provider.id}`,
          );
          if (provider)
            void present(ProviderEditorScreen, {
              ...scope,
              item: provider,
            }).then(() => void load());
        }}
      />
    </>
  );
}

function View() {
  const { selected } = useCatalog();
  if (!selected) return null;
  return <ProviderManagementView key={selected.id} workspaceId={selected.id} />;
}

export const ProviderManagementScreen = definePage({
  id: 'providers',
  title: t('providers.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
