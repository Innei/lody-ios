import { useState } from 'react';
import { PlatformColor, View } from 'react-native';
import { NativeCodeView } from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { AppText } from '@/ui/AppText';
import { t } from '../../../i18n/index.ts';

export type FileParams = { path: string; handle: string; bytes: number };

function FileScreen() {
  const { params } = usePageRuntime<FileParams>();
  const [error, setError] = useState('');
  return (
    <View
      style={{ flex: 1, backgroundColor: PlatformColor('systemBackground') }}
    >
      {error ? (
        <AppText variant="meta" style={{ padding: 24, textAlign: 'center' }}>
          {error}
        </AppText>
      ) : (
        <NativeCodeView
          style={{ flex: 1 }}
          path={params.path}
          handle={params.handle}
          onFail={({ nativeEvent }) =>
            setError(
              nativeEvent.message === 'content_expired'
                ? t('file.error.stale')
                : t('file.error.render'),
            )
          }
        />
      )}
    </View>
  );
}

export const filePage = definePage<FileParams>({
  id: 'file',
  title: t('file.title'),
  Component: FileScreen,
  parseRouteParams: () => {
    throw new Error('请从项目文件打开');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
