import { useMemo } from 'react';
import { useColorScheme } from 'react-native';
import { useAppearance } from './appearance';
import { navigationThemes, usePalette } from './palette';
import { softDarkBackground } from './tokens';

export function useNavigationTheme() {
  const colorScheme = useColorScheme();
  const { darkBackground } = useAppearance();
  const colors = usePalette();
  return useMemo(() => {
    const base =
      colorScheme === 'dark' ? navigationThemes.dark : navigationThemes.light;
    return {
      ...base,
      colors: {
        ...base.colors,
        primary: colors.accent,
        background:
          colorScheme === 'dark' && darkBackground === 'soft'
            ? softDarkBackground
            : base.colors.background,
      },
    };
  }, [colorScheme, darkBackground, colors.accent]);
}
