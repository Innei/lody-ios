export const accent = {
  light: '#3B4FD9',
  dark: '#7B8AFF',
} as const;

export const systemBackground = {
  light: '#FFFFFF',
  dark: '#000000',
} as const;

export const systemGroupedBackground = {
  light: '#F2F2F7',
  dark: '#000000',
} as const;

export const opaqueCard = {
  light: '#FFFFFF',
  dark: '#1C1C1E',
} as const;

/** Recessed chat chips; light `neutral-100`, dark `secondarySystemBackground`. */
export const inset = {
  light: '#F5F5F5',
  dark: '#1C1C1E',
} as const;

export const label = {
  light: '#000000',
  dark: '#FFFFFF',
} as const;

export const separator = {
  light: '#C6C6C8',
  dark: '#38383A',
} as const;

export const danger = {
  light: '#FF3B30',
  dark: '#FF453A',
} as const;

export const onAccent = '#FFFFFF';

export const type = {
  title: { size: 20, lineHeight: 26 },
  body: { size: 17, lineHeight: 25 },
  secondary: { size: 15, lineHeight: 21 },
  meta: { size: 13, lineHeight: 18 },
  eyebrow: { size: 11, lineHeight: 14, letterSpacing: 0.88 },
  mono: { size: 13, lineHeight: 20 },
} as const;

export const space = [4, 8, 12, 16, 20, 24] as const;

/** Extra Small / default Large body (17pt). */
export const FONT_SCALE_MIN = 14 / 17;
/** XXXL / default Large body. Accessibility AX* sizes are not followed. */
export const FONT_SCALE_MAX = 23 / 17;

export function clampFontScale(fontScale: number) {
  return Math.min(FONT_SCALE_MAX, Math.max(FONT_SCALE_MIN, fontScale));
}

export type ThemeName = keyof typeof accent;
export type TypeRole = keyof typeof type;

function channel(value: number) {
  const srgb = value / 255;
  return srgb <= 0.040_45 ? srgb / 12.92 : ((srgb + 0.055) / 1.055) ** 2.4;
}

export function luminance(hex: string) {
  const value = Number.parseInt(hex.slice(1), 16);
  return (
    0.2126 * channel((value >> 16) & 0xff) +
    0.7152 * channel((value >> 8) & 0xff) +
    0.0722 * channel(value & 0xff)
  );
}

export function contrastRatio(a: string, b: string) {
  const [dark, light] = [luminance(a), luminance(b)].sort((x, y) => x - y);
  return (light + 0.05) / (dark + 0.05);
}
