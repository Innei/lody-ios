import { accentHex, accentForegroundHex } from '@lody-ios/kit';
import { PlatformColor, useColorScheme } from 'react-native';
import { useAppearance } from './appearance';
import {
  accent,
  danger,
  inset,
  label,
  opaqueCard,
  separator,
  softDarkBackground,
  systemGroupedBackground,
  type ThemeName,
} from './tokens';

export type ColorRole =
  | 'label'
  | 'secondaryLabel'
  | 'tertiaryLabel'
  | 'accent'
  | 'warning'
  | 'danger'
  | 'background'
  | 'reading'
  | 'card'
  | 'inset'
  | 'separator'
  | 'fill'
  | 'onAccent';

export function usePalette() {
  const theme: ThemeName = useColorScheme() === 'dark' ? 'dark' : 'light';
  const { darkBackground, accentColor } = useAppearance();
  const comfortable = theme === 'dark' && darkBackground === 'soft';
  return {
    theme,
    label: PlatformColor('label'),
    secondaryLabel: PlatformColor('secondaryLabel'),
    tertiaryLabel: PlatformColor('tertiaryLabel'),
    accent: accentHex(accentColor, theme === 'dark'),
    warning: PlatformColor('systemOrange'),
    danger: PlatformColor('systemRed'),
    background: comfortable
      ? softDarkBackground
      : PlatformColor('systemGroupedBackground'),
    reading: comfortable
      ? softDarkBackground
      : PlatformColor('systemBackground'),
    card: PlatformColor('secondarySystemGroupedBackground'),
    inset: inset[theme],
    separator: PlatformColor('separator'),
    fill: PlatformColor('tertiarySystemFill'),
    onAccent: accentForegroundHex(accentColor),
  } as const;
}

export type Palette = ReturnType<typeof usePalette>;

/** Navigation needs plain string colors; native surfaces use adaptive UIKit colors. */
export const navigationThemes = {
  light: {
    dark: false,
    colors: {
      primary: accent.light,
      background: systemGroupedBackground.light,
      card: opaqueCard.light,
      text: label.light,
      border: separator.light,
      notification: danger.light,
    },
  },
  dark: {
    dark: true,
    colors: {
      primary: accent.dark,
      background: systemGroupedBackground.dark,
      card: opaqueCard.dark,
      text: label.dark,
      border: separator.dark,
      notification: danger.dark,
    },
  },
} as const;
