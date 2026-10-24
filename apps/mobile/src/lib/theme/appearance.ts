import { saveAccentColor, saveDarkBackground } from '@lody-ios/kit';
import { setPreferences, usePreferences } from '@/lib/preferences';

export const accentChoices = ['blue', 'indigo', 'purple', 'pink'] as const;
export type AccentColor = (typeof accentChoices)[number] | `#${string}`;

export function isAccentColor(value: string): value is AccentColor {
  return (
    accentChoices.some((choice) => choice === value) ||
    (value.length === 7 && /^#[0-9a-f]{6}$/i.test(value))
  );
}

export type DarkBackground = 'soft' | 'black';

function setAccentColor(value: AccentColor) {
  setPreferences({ accentColor: value });
  saveAccentColor(value);
}

function setDarkBackground(value: DarkBackground) {
  setPreferences({ darkBackground: value });
  saveDarkBackground(value);
}

export function useAppearance() {
  const { accentColor, darkBackground } = usePreferences();
  return {
    accentColor: isAccentColor(accentColor) ? accentColor : 'blue',
    setAccentColor,
    darkBackground: (darkBackground === 'black'
      ? 'black'
      : 'soft') as DarkBackground,
    setDarkBackground,
  };
}
