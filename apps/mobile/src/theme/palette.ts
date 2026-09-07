import { PlatformColor, useColorScheme } from 'react-native';
import { DarkTheme, DefaultTheme } from 'expo-router';
import {
  accent,
  danger,
  inset,
  label,
  onAccent,
  opaqueCard,
  separator,
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
  return {
    theme,
    label: PlatformColor('label'),
    secondaryLabel: PlatformColor('secondaryLabel'),
    tertiaryLabel: PlatformColor('tertiaryLabel'),
    accent: accent[theme],
    warning: PlatformColor('systemOrange'),
    danger: PlatformColor('systemRed'),
    background: PlatformColor('systemGroupedBackground'),
    reading: PlatformColor('systemBackground'),
    card: PlatformColor('secondarySystemGroupedBackground'),
    inset: inset[theme],
    separator: PlatformColor('separator'),
    fill: PlatformColor('tertiarySystemFill'),
    onAccent,
  } as const;
}

export type Palette = ReturnType<typeof usePalette>;

/** Navigation needs plain string colors; native surfaces use adaptive UIKit colors. */
export const navigationThemes = {
  light: {
    ...DefaultTheme,
    colors: {
      ...DefaultTheme.colors,
      primary: accent.light,
      background: systemGroupedBackground.light,
      card: opaqueCard.light,
      text: label.light,
      border: separator.light,
      notification: danger.light,
    },
  },
  dark: {
    ...DarkTheme,
    colors: {
      ...DarkTheme.colors,
      primary: accent.dark,
      background: systemGroupedBackground.dark,
      card: opaqueCard.dark,
      text: label.dark,
      border: separator.dark,
      notification: danger.dark,
    },
  },
} as const;
