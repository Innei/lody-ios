import en from '../../locales/en.json' with { type: 'json' };
import zhHans from '../../locales/zh-Hans.json' with { type: 'json' };
import type { Locale, TemplateVars } from './format.ts';
import { formatTemplate, pluralSuffix } from './format.ts';

export type { Locale, TemplateVars } from './format.ts';
export { matchLocale } from './format.ts';

export type TranslationKey = keyof typeof zhHans;

type PluralBase<K> = K extends `${infer Base}.one`
  ? `${Base}.other` extends TranslationKey
    ? Base
    : never
  : never;

export type PluralKey = PluralBase<TranslationKey>;

const catalogs: Record<Locale, Record<TranslationKey, string>> = {
  'zh-Hans': zhHans,
  en,
};

let locale: Locale = 'en';
let catalog = catalogs[locale];

/** Set once from the entry module, before any route or native prop reads copy. */
export function setLocale(next: Locale) {
  locale = next;
  catalog = catalogs[next];
}

export function currentLocale() {
  return locale;
}

export function t(key: TranslationKey, vars?: TemplateVars) {
  return formatTemplate(catalog[key] ?? key, vars);
}

export function tp(key: PluralKey, count: number, vars?: TemplateVars) {
  const exact = `${key}${pluralSuffix(locale, count)}` as TranslationKey;
  const template = catalog[exact] ?? catalog[`${key}.other` as TranslationKey];
  return formatTemplate(template ?? key, vars);
}
