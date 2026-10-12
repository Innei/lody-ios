import { NativeGroupedList } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { providerKinds } from '@/features/providers/provider-config';
import type { ProviderConfig } from '@lody/cloud-runtime/models/providers';
import { t } from '@/lib/i18n';

type Choice = { id: string; name: string };
type Params = { choices?: Choice[]; selected?: string };

function View() {
  const { params, finish } = usePageRuntime<Params, string>();
  const choices = params.choices ?? [
    ...providerKinds.map(([id, name]) => ({ id, name })),
    { id: 'registry', name: t('providers.registry') },
    { id: 'custom', name: t('providers.custom') },
  ];
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      sections={[
        {
          id: 'provider-choices',
          rows: choices.map((choice) => ({
            id: `provider-choice:${choice.id}`,
            title: choice.name,
            selected: params.selected === choice.id,
            action: true,
          })),
        },
      ]}
      onRowPress={({ nativeEvent: { id } }) =>
        finish(id.slice('provider-choice:'.length))
      }
    />
  );
}

export const ProviderChoiceScreen = definePage<Params, string>({
  id: 'provider-choice',
  title: t('providers.choose'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from Provider management');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [0.7, 1],
  },
});

export function providerChoiceType(choice: string): ProviderConfig['cliType'] {
  if (choice === 'custom' || choice === 'registry') return choice;
  return 'builtin';
}
