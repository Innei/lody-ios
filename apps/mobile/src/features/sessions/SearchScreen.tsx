import { Stack } from 'expo-router';
import { useState } from 'react';
import { NativeGroupedList } from '@lody-ios/kit';
import { useCatalog } from '@/cloud/CatalogProvider';
import { usePalette } from '@/theme/palette';
import { useAuth } from '@/features/auth/AuthProvider';
import { searchPlaceholder } from '@/ui/listState';
import { searchSections } from './inbox';
import { openCatalogRow } from './navigation';

export default function SearchScreen() {
  const { catalog, loading, connected } = useCatalog();
  const { account } = useAuth();
  const colors = usePalette();
  const [query, setQuery] = useState('');
  return (
    <>
      <Stack.SearchBar
        placement="automatic"
        placeholder="搜索项目或会话"
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
