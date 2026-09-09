import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { licenseEntry, licenseText } from '@/features/licenses';
import { AppText } from '@/ui/AppText';
import { Screen } from '@/ui/Screen';
import { t } from '../lib/i18n/index.ts';

export type LicenseDetailParams = { name: string };

function View() {
  const { params } = usePageRuntime<LicenseDetailParams>();
  const entry = licenseEntry(params.name);
  if (!entry)
    return (
      <Screen>
        <AppText variant="secondary">{t('settings.licenses.missing')}</AppText>
      </Screen>
    );
  return (
    <Screen>
      <AppText variant="title">{entry.name}</AppText>
      <AppText variant="secondary">
        {[entry.version && `v${entry.version}`, entry.license]
          .filter(Boolean)
          .join(' · ')}
      </AppText>
      {entry.url ? (
        <AppText variant="secondary" selectable>
          {entry.url}
        </AppText>
      ) : null}
      <AppText variant="mono" selectable>
        {licenseText(entry)}
      </AppText>
    </Screen>
  );
}

export const LicenseDetailScreen = definePage<LicenseDetailParams>({
  id: 'license-detail',
  title: t('settings.licenses.title'),
  Component: View,
  parseRouteParams: ({ name }) => ({
    name: (Array.isArray(name) ? name[0] : name) ?? '',
  }),
  presentation: { style: 'push', headerVariant: 'transparent' },
});
