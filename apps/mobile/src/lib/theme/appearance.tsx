import {
  initialDarkBackground,
  saveDarkBackground,
  initialAccentColor,
  saveAccentColor,
} from '@lody-ios/kit';
import {
  createContext,
  type PropsWithChildren,
  use,
  useCallback,
  useMemo,
  useState,
} from 'react';

export const accentChoices = ['blue', 'indigo', 'purple', 'pink'] as const;
export type AccentColor = (typeof accentChoices)[number];
export function isAccentColor(value: string): value is AccentColor {
  return accentChoices.some((choice) => choice === value);
}

export type DarkBackground = 'soft' | 'black';

const initial: DarkBackground =
  initialDarkBackground === 'black' ? 'black' : 'soft';

const AppearanceContext = createContext<{
  accentColor: AccentColor;
  setAccentColor: (value: AccentColor) => void;
  darkBackground: DarkBackground;
  setDarkBackground: (value: DarkBackground) => void;
} | null>(null);

export function AppearanceProvider({ children }: PropsWithChildren) {
  const [accentColor, setAccent] = useState<AccentColor>(
    isAccentColor(initialAccentColor) ? initialAccentColor : 'blue',
  );
  const setAccentColor = useCallback((value: AccentColor) => {
    saveAccentColor(value);
    setAccent(value);
  }, []);
  const [darkBackground, setValue] = useState(initial);
  const setDarkBackground = useCallback((value: DarkBackground) => {
    saveDarkBackground(value);
    setValue(value);
  }, []);
  const value = useMemo(
    () => ({ darkBackground, setDarkBackground, accentColor, setAccentColor }),
    [darkBackground, setDarkBackground, accentColor, setAccentColor],
  );
  return <AppearanceContext value={value}>{children}</AppearanceContext>;
}

export function useAppearance() {
  const value = use(AppearanceContext);
  if (!value)
    throw new Error('useAppearance must be used inside AppearanceProvider');
  return value;
}
