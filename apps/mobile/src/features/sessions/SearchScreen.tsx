import { Stack } from 'expo-router';
import { useState } from 'react';
import { NativeGroupedList } from '@lody-ios/kit';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePalette } from '@/theme/palette';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { searchPlaceholder } from '@/ui/listState';
import { searchSections } from './inbox';
import { openCatalogRow } from './navigation';
import { t } from '../../i18n/index.ts';

export default function SearchScreen() {
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
