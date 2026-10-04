import { ComposerHandoffPOC } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

function Preview() {
  const runtime = usePageRuntime();
  return <ComposerHandoffPOC style={{ flex: 1 }} onClose={runtime.cancel} />;
}

export const ComposerHandoffPreviewScreen = definePage({
  id: 'composer-relay',
  title: 'Composer 接力 POC',
  Component: Preview,
  presentation: { style: 'push', headerShown: false },
});
