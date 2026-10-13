import { useEffect, useMemo, useState } from 'react';
import { Text, View } from 'react-native';
import { debugSeedDiagnostics } from '@lody-ios/kit';
import {
  diagnosticsService,
  type DiagnosticsService,
} from '@/features/diagnostics/service';
import { DiagnosticsContent } from '@/screens/DiagnosticsScreen';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { Button } from '@/ui/Button';

function Preview() {
  const colors = usePalette();
  const [revision, setRevision] = useState(0);
  const [ready, setReady] = useState(false);
  const [readFailure, setReadFailure] = useState(false);
  const [clearFailure, setClearFailure] = useState(false);
  const service = useMemo<DiagnosticsService>(() => {
    let rejectExport = true;
    return {
      count: async (window) => {
        if (readFailure) throw new Error('Injected diagnostic read failure');
        return diagnosticsService.count(window);
      },
      share: async (window) => {
        if (rejectExport) {
          rejectExport = false;
          throw new Error('Injected diagnostic export failure');
        }
        await diagnosticsService.share(window);
      },
      clear: async () => {
        if (clearFailure) throw new Error('Injected diagnostic clear failure');
        await diagnosticsService.clear();
      },
    };
  }, [revision, readFailure, clearFailure]);
  useEffect(() => {
    let active = true;
    setReady(false);
    void debugSeedDiagnostics().then(() => {
      if (active) setReady(true);
    });
    return () => {
      active = false;
    };
  }, [revision]);

  return (
    <View style={{ flex: 1 }}>
      <View style={{ paddingTop: 110, paddingHorizontal: 20 }}>
        <Text
          style={{ color: colors.label }}
          testID="diagnostics-preview-ready"
        >
          Offline diagnostic fixture
        </Text>
        <View style={{ flexDirection: 'row', gap: 10 }}>
          <Button
            testID="diagnostics-reset"
            onPress={() => {
              setReadFailure(false);
              setClearFailure(false);
              setRevision((value) => value + 1);
            }}
          >
            Reset
          </Button>
          <Button
            testID="diagnostics-read-failure"
            onPress={() => setReadFailure((value) => !value)}
          >
            Read failure
          </Button>
          <Button
            testID="diagnostics-clear-failure"
            onPress={() => setClearFailure((value) => !value)}
          >
            Clear failure
          </Button>
        </View>
      </View>
      {ready && <DiagnosticsContent key={revision} service={service} />}
    </View>
  );
}

export const DiagnosticsPreviewScreen = definePage({
  id: 'diagnostics-preview',
  title: 'Diagnostics',
  Component: Preview,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
