import { useEffect } from 'react';
import { StyleSheet } from 'react-native';
import { NativeLayoutProbe } from '@lody-ios/kit';
import { PushCoordinator } from '@/features/notifications/PushCoordinator';
import { ShareCoordinator } from '@/features/share/ShareCoordinator';
import { ShareSnapshot } from '@/features/share/ShareSnapshot';
import { useBindSessionNav } from '@/hooks/screens/useBindSessionNav';
import { useOnboardingGate } from '@/hooks/screens/useOnboardingGate';
import { present } from '@/lib/presentation';
import { setLayoutTraits } from '@/lib/presentation/layoutMode';
import { uiVerify } from '@/lib/uiVerify';
import { DebugScreen } from '@/screens/debug/DebugScreen';
import { homeVerify } from '@/screens/debug/HomePreviewScreen';
import { HomeScreen } from '@/screens/HomeScreen';

let started = false;

export function ShellRoot() {
  useBindSessionNav();
  useOnboardingGate();
  useEffect(() => {
    if (started) return;
    started = true;
    const root = uiVerify && !homeVerify ? DebugScreen : HomeScreen;
    void present(root, undefined as never, { root: true });
  }, []);
  return (
    <>
      <NativeLayoutProbe
        pointerEvents="none"
        style={StyleSheet.absoluteFill}
        onTraits={({ nativeEvent }) => setLayoutTraits(nativeEvent)}
      />
      <PushCoordinator />
      <ShareSnapshot />
      <ShareCoordinator />
    </>
  );
}
