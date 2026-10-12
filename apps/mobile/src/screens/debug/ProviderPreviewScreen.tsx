import { useMemo, useState } from 'react';
import { View } from 'react-native';
import { definePage } from '@/lib/presentation';
import { createProviderFixture } from '@/features/providers/preview';
import { Button } from '@/ui/Button';
import { t } from '@/lib/i18n';
import { ProviderManagementView } from '../ProviderManagementScreen';

function Preview() {
  const [generation, setGeneration] = useState(0);
  const service = useMemo(createProviderFixture, [generation]);
  return (
    <View style={{ flex: 1 }}>
      <ProviderManagementView
        key={generation}
        workspaceId="offline-providers"
        service={service}
      />
      <Button
        testID="providers-reset"
        label={t('providers.reset')}
        onPress={() => setGeneration((value) => value + 1)}
      />
    </View>
  );
}

export const ProviderPreviewScreen = definePage({
  id: 'providers-preview',
  title: t('providers.title'),
  Component: Preview,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
