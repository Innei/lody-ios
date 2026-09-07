declare const __DEV__: boolean | undefined;

export type Locale = 'zh-Hans' | 'en';

export type TemplateVars = Record<string, string | number>;

const PLACEHOLDER = /\{([A-Za-z][A-Za-z0-9_]*)\}/g;

export function matchLocale(tag: string | undefined | null): Locale {
  const lower = (tag ?? '').toLowerCase();
  if (lower === 'zh' || /^zh-(hans|cn|sg)\b/.test(lower)) return 'zh-Hans';
  if (lower === 'en' || lower.startsWith('en-')) return 'en';
  return 'en';
}

export function placeholders(template: string) {
  return new Set(Array.from(template.matchAll(PLACEHOLDER), (m) => m[1]));
}

export function formatTemplate(template: string, vars?: TemplateVars) {
  return template.replace(PLACEHOLDER, (match, name: string) => {
    const value = vars?.[name];
    if (typeof value === 'string') return value;
    if (typeof value === 'number' && Number.isFinite(value))
      return String(value);
    if (typeof __DEV__ !== 'undefined' && __DEV__)
      console.warn(`i18n: missing variable ${name}`);
    return match;
  });
}

/**
 * Hermes ships no `Intl.PluralRules`, so the two supported cardinal rules live
 * here: English separates 1, Simplified Chinese never does.
 */
export function pluralSuffix(locale: Locale, count: number) {
  return locale === 'en' && count === 1 ? ('.one' as const) : ('.other' as const);
}
