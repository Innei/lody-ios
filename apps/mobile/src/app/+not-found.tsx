import { useCallback } from 'react';
import { router, useFocusEffect } from 'expo-router';

export default function NotFound() {
  useFocusEffect(useCallback(() => router.dismissTo('/'), []));
  return null;
}
