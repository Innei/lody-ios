import { type PropsWithChildren, useEffect, useSyncExternalStore } from 'react';
import {
  type EdgeInsets,
  initialWindowMetrics,
  type Rect,
  SafeAreaFrameContext,
  SafeAreaInsetsContext,
  useSafeAreaFrame,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';

type Metrics = { insets: EdgeInsets; frame: Rect };

// Pages read the window's insets, not their own controller's, which include the
// navigation bar; every page reuses the root surface's values.
let metrics: Metrics = initialWindowMetrics ?? {
  insets: { top: 0, right: 0, bottom: 0, left: 0 },
  frame: { x: 0, y: 0, width: 0, height: 0 },
};
const listeners = new Set<() => void>();

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

const same = (a: object, b: object) => JSON.stringify(a) === JSON.stringify(b);

export function PublishSafeArea() {
  const insets = useSafeAreaInsets();
  const frame = useSafeAreaFrame();
  useEffect(() => {
    if (same(metrics.insets, insets) && same(metrics.frame, frame)) return;
    metrics = { insets, frame };
    for (const listener of listeners) listener();
  }, [insets, frame]);
  return null;
}

export function PageSafeArea({ children }: PropsWithChildren) {
  const current = useSyncExternalStore(subscribe, () => metrics);
  return (
    <SafeAreaFrameContext value={current.frame}>
      <SafeAreaInsetsContext value={current.insets}>
        {children}
      </SafeAreaInsetsContext>
    </SafeAreaFrameContext>
  );
}
