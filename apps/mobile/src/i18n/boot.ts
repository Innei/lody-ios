import { getLocales } from 'expo-localization';

import { matchLocale } from './format.ts';
import { setLocale } from './index.ts';

setLocale(matchLocale(getLocales()[0]?.languageTag));
