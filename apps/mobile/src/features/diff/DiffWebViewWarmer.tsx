import { useEffect, useState } from 'react';
import {
  StyleSheet,
  useColorScheme,
  useWindowDimensions,
  View,
} from 'react-native';
import { InteractionManager } from 'react-native';
import { DiffView } from './DiffView';

export function DiffWebViewWarmer() {
  const [live, setLive] = useState(false);
  const { height, width } = useWindowDimensions();
  const theme = useColorScheme() === 'dark' ? 'dark' : 'light';

  useEffect(() => {
    const interaction = InteractionManager.runAfterInteractions(() => {
      setLive(true);
    });
    return () => interaction.cancel();
  }, []);

  useEffect(() => {
    if (!live) return;
    const timer = setTimeout(() => setLive(false), 4_000);
    return () => clearTimeout(timer);
  }, [live]);

  if (!live) return null;
  return (
    <View
      pointerEvents="none"
      style={[styles.host, { height, left: -width, width }]}
    >
      <DiffView
        path=""
        oldText=""
        newText=""
        diffStyle="unified"
        theme={theme}
        warm
        dom={{
          shared: true,
          matchContents: false,
          scrollEnabled: false,
          contentInsetAdjustmentBehavior: 'never',
          style: { height, width },
          onMessage: (event) => {
            try {
              const payload = JSON.parse(event.nativeEvent.data) as {
                type?: string;
              };
              if (payload.type === 'lody:diff-runtime-ready') setLive(false);
            } catch {
              /* ignore */
            }
          },
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  host: {
    overflow: 'hidden',
    position: 'absolute',
    top: 0,
  },
});
