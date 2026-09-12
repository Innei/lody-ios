import { useState } from 'react';
import { Pressable, ScrollView, Text, TextInput, View } from 'react-native';
import { NativePagePOC, NativeShellPOC } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

function Content({
  role,
  search = '',
  cancelled = 0,
}: {
  role: 'root' | 'project' | 'detail';
  search?: string;
  cancelled?: number;
}) {
  const colors = usePalette();
  const [count, setCount] = useState(0);
  const [draft, setDraft] = useState('');
  return (
    <View style={{ flex: 1 }} testID={`native-shell-${role}`}>
      <ScrollView
        style={{ flex: 1 }}
        contentInsetAdjustmentBehavior="never"
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={{ padding: 16, gap: 12 }}
      >
        <Text style={{ color: colors.label }}>
          React {role} · cancelled pops: {cancelled}
        </Text>
        <Pressable
          testID={`poc-${role}-counter`}
          accessibilityRole="button"
          onPress={() => setCount(count + 1)}
          style={{ minHeight: 44, justifyContent: 'center' }}
        >
          <Text style={{ color: colors.accent }}>
            {role} count: {count}
          </Text>
        </Pressable>
        <TextInput
          testID={`poc-${role}-draft`}
          accessibilityLabel={`${role} draft`}
          placeholder="React draft"
          autoCapitalize="none"
          autoCorrect={false}
          value={draft}
          onChangeText={setDraft}
          style={{
            minHeight: 44,
            color: colors.label,
            borderWidth: 1,
            borderColor: colors.separator,
            padding: 8,
          }}
        />
        {Array.from({ length: 30 }, (_, i) => `Session ${i + 1}`)
          .filter((text) => text.toLowerCase().includes(search.toLowerCase()))
          .map((text) => (
            <Text key={text} style={{ color: colors.label, minHeight: 44 }}>
              {text} — React content wraps inside the native column.
            </Text>
          ))}
      </ScrollView>
    </View>
  );
}

function Preview() {
  const runtime = usePageRuntime();
  const [project, setProject] = useState(false);
  const [search, setSearch] = useState('');
  const [cancelled, setCancelled] = useState(0);
  return (
    <NativeShellPOC
      style={{ flex: 1 }}
      testID="native-shell-ready"
      onAction={({ nativeEvent: event }) => {
        if (event.action === 'close') runtime.cancel();
        if (event.action === 'openProject') setProject(true);
        if (event.action === 'projectClosed') setProject(false);
        if (event.action === 'search') setSearch(event.text ?? '');
        if (event.action === 'cancelledPop') setCancelled(event.count ?? 0);
      }}
    >
      <NativePagePOC pageKind="root" style={{ position: 'absolute' }}>
        <Content role="root" search={search} />
      </NativePagePOC>
      <NativePagePOC pageKind="detail" style={{ position: 'absolute' }}>
        <Content role="detail" />
      </NativePagePOC>
      {project && (
        <NativePagePOC pageKind="project" style={{ position: 'absolute' }}>
          <Content role="project" cancelled={cancelled} />
        </NativePagePOC>
      )}
    </NativeShellPOC>
  );
}

export const NativeShellPreviewScreen = definePage({
  id: 'native-shell-poc',
  title: 'Native Shell POC',
  Component: Preview,
  presentation: { style: 'push', headerShown: false },
});

function CollectionPreview() {
  const runtime = usePageRuntime();
  return (
    <NativeShellPOC
      collectionSidebar
      style={{ flex: 1 }}
      onAction={({ nativeEvent }) => {
        if (nativeEvent.action === 'close') runtime.cancel();
      }}
    >
      <NativePagePOC pageKind="detail" style={{ position: 'absolute' }}>
        <Content role="detail" />
      </NativePagePOC>
    </NativeShellPOC>
  );
}

export const NativeCollectionPreviewScreen = definePage({
  id: 'native-collection-poc',
  title: 'Native Collection POC',
  Component: CollectionPreview,
  presentation: { style: 'push', headerShown: false },
});
