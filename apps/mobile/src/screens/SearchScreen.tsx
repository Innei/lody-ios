import { Stack } from 'expo-router';
import { useState } from 'react';
import { NativeGroupedList } from '@lody-ios/kit';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePalette } from '@/theme/palette';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { searchPlaceholder } from '@/ui/listState';
import { searchSections } from '@/features/sessions/inbox';
import { openCatalogRow } from '@/hooks/screens/openCatalogRow';
import { definePage } from '@/presentation';
import { t } from '../i18n/index.ts';

function View() {
  const { catalog, loading, connected } = useCatalog();
  const { account } = useAuth();
  const colors = usePalette();
  const [query, setQuery] = useState('');
  return (
    <>
      <Stack.SearchBar
        placement="automatic"
        placeholder={t('search.field.placeholder')}
        hideWhenScrolling={false}
        onChangeText={({ nativeEvent }) => setQuery(nativeEvent.text)}
        onCancelButtonPress={() => setQuery('')}
      />
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        contentStyle
        sections={account ? searchSections(catalog, query, colors.accent) : []}
        placeholder={searchPlaceholder({
          signedIn: !!account,
          query,
          loading,
          connected,
        })}
        onRowPress={({ nativeEvent }) =>
          openCatalogRow(nativeEvent.id, catalog)
        }
      />
    </>
  );
}

export const SearchScreen = definePage({
  id: 'search',
  title: t('tabs.search'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
