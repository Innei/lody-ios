import {
  useFocusEffect as useRouterFocusEffect,
  useIsFocused as useRouterIsFocused,
} from 'expo-router';
import { shellEnabled } from '@lody-ios/kit';

import { useShellFocusEffect, useShellIsFocused } from './shellNavigation';

export const useFocusEffect = shellEnabled
  ? useShellFocusEffect
  : useRouterFocusEffect;
export const useIsFocused = shellEnabled
  ? useShellIsFocused
  : useRouterIsFocused;
