// Expo inlines this flag into the development bundle. Release builds cannot opt in.
export const uiVerify = __DEV__ && process.env.EXPO_PUBLIC_UI_VERIFY === '1';
