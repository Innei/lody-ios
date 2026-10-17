import type { PagePresentationStyle } from './page';

export function sheetContentBackground<T>(
  style: PagePresentationStyle,
  backgroundColor: T,
  regularWidth: boolean,
): T | 'transparent' {
  if (style === 'overFullScreen') return 'transparent';
  if (!regularWidth && (style === 'formSheet' || style === 'pageSheet')) {
    return 'transparent';
  }
  return backgroundColor;
}
