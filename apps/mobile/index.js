import 'expo-asset';
import './src/lib/i18n/boot.ts';
import { shellEnabled } from '@lody-ios/kit';

if (shellEnabled) require('./src/shell/register');
else require('expo-router/entry');
