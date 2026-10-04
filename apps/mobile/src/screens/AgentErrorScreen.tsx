import { useState } from 'react';
import { copyText } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { t } from '@/lib/i18n/index.ts';
import type { SystemNoticeMeta } from '@/models/session';
import { Screen } from '@/ui/Screen';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';

function View() {
  const { params } = usePageRuntime<SystemNoticeMeta>();
  const [copied, setCopied] = useState(false);
  const report =
    [params.reason, params.code, params.message]
      .filter((value) => value?.trim())
      .join('\n\n') || t('native.chat.error.unknown');
  return (
    <Screen>
      <Button
        testID="agent-error-copy"
        label={t(
          copied ? 'native.chat.error.copied' : 'native.chat.error.copy',
        )}
        onPress={() => {
          copyText(report);
          setCopied(true);
        }}
      />
      <AppText testID="agent-error-report" variant="mono" selectable>
        {report}
      </AppText>
    </Screen>
  );
}

export const AgentErrorScreen = definePage<SystemNoticeMeta>({
  id: 'agent-error',
  title: t('native.chat.error.detail'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from a chat error');
  },
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [0.6, 1],
    sheetInitialDetentIndex: 0,
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});
