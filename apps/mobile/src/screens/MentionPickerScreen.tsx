import { use, useEffect, useRef, useState } from 'react';
import type { SearchBarCommands } from 'react-native-screens';
import { SheetSearchContext } from '@/lib/presentation/SheetStack';
import { t } from '@/lib/i18n';
import { NativeGroupedList, NativeMentionPicker } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import type { MentionCatalog, MentionItem } from '@/models/mentions';

type Params = {
  category: string;
  query: string;
  items?: MentionItem[];
  initial?: MentionCatalog;
  load?: (refresh: boolean) => Promise<MentionCatalog>;
};

function View() {
  const { params, finish } = usePageRuntime<Params, MentionItem>();
  const colors = usePalette();
  const [query, setQuery] = useState(params.query);
  const [catalog, setCatalog] = useState(params.initial);
  const [loading, setLoading] = useState(!!params.load && !params.initial);
  const [error, setError] = useState(false);
  const [revision, setRevision] = useState(0);
  const search = useRef<SearchBarCommands>(null);
  const setSearch = use(SheetSearchContext);
  useEffect(() => {
    if (!params.load) return;
    let active = true;
    setLoading(!catalog || revision > 0);
    setError(false);
    params
      .load(revision > 0)
      .then((value) => {
        if (active) setCatalog(value);
      })
      .catch(() => {
        if (active) setError(true);
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [params.load, revision]);
  useEffect(() => {
    setSearch?.({
      ref: search,
      placement: 'integrated',
      placeholder: t('native.chat.mention.open'),
      autoCapitalize: 'none',
      hideNavigationBar: false,
      obscureBackground: false,
      onChangeText: ({ nativeEvent }) => setQuery(nativeEvent.text),
      onCancelButtonPress: () => setQuery(''),
    });
    return () => setSearch?.(undefined);
  }, [setSearch]);
  if (loading || error)
    return (
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        sections={
          error
            ? [
                {
                  id: 'error',
                  footer: t('mentions.error'),
                  rows: [
                    { id: 'retry', title: t('common.retry'), action: true },
                  ],
                },
              ]
            : []
        }
        placeholder={loading ? t('common.reading') : t('mentions.error')}
        onRowPress={() => setRevision((value) => value + 1)}
      />
    );
  const items = catalog?.items ?? params.items ?? [];
  let notice = '';
  if (catalog?.incomplete) notice = t('mentions.incomplete');
  else if (catalog?.truncated) notice = t('mentions.truncated');
  return (
    <NativeMentionPicker
      style={{ flex: 1 }}
      configurationJSON={JSON.stringify({
        category: params.category,
        items,
        query,
        notice,
      })}
      onRetry={() => setRevision((value) => value + 1)}
      onQueryReset={() => {
        setQuery('');
        search.current?.clearText();
        search.current?.cancelSearch();
      }}
      onPick={({ nativeEvent }) => {
        const item = items.find((value) => value.path === nativeEvent.path);
        if (item) finish(item);
      }}
    />
  );
}

export const MentionPickerScreen = definePage<Params, MentionItem>({
  id: 'mention-picker',
  title: t('native.chat.mention.open'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from a composer');
  },
  presentation: { style: 'fullScreen', headerVariant: 'transparent' },
});
