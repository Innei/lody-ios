import { initialLocale } from '@lody-ios/kit';

import { matchLocale } from './format.ts';
import { setLocale } from './index.ts';

// Use the same supported localization as native strings, including fallbacks.
setLocale(matchLocale(initialLocale));
