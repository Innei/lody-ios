import { initialDarkBackground, saveDarkBackground } from '@lody-ios/kit';
import {
  createContext,
  type PropsWithChildren,
  use,
  useCallback,
  useMemo,
  useState,
} from 'react';

export type DarkBackground = 'soft' | 'black';

const initial: DarkBackground =
  initialDarkBackground === 'black' ? 'black' : 'soft';

const AppearanceContext = createContext<{
  darkBackground: DarkBackground;
  setDarkBackground: (value: DarkBackground) => void;
} | null>(null);

export function AppearanceProvider({ children }: PropsWithChildren) {
  const [darkBackground, setValue] = useState(initial);
  const setDarkBackground = useCallback((value: DarkBackground) => {
    saveDarkBackground(value);
    setValue(value);
  }, []);
  const value = useMemo(
    () => ({ darkBackground, setDarkBackground }),
    [darkBackground, setDarkBackground],
  );
  return <AppearanceContext value={value}>{children}</AppearanceContext>;
}

export function useAppearance() {
  const value = use(AppearanceContext);
  if (!value)
    throw new Error('useAppearance must be used inside AppearanceProvider');
  return value;
}
