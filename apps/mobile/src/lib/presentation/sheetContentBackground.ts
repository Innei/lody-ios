import type { PagePresentationStyle } from './page';

export function sheetContentBackground<T>(
  style: PagePresentationStyle,
  backgroundColor: T,
  isPad: boolean,
): T | 'transparent' {
  if (style === 'overFullScreen') return 'transparent';
  if (!isPad && (style === 'formSheet' || style === 'pageSheet')) {
    return 'transparent';
  }
  return backgroundColor;
}
