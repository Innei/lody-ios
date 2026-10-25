import { definePage } from '@/lib/presentation';

const presentation = { headerVariant: 'transparent' } as const;

export const PublishedSharesPreviewScreen = definePage({
  id: 'published-shares-preview',
  title: 'Published Shares',
  native: true,
  presentation,
});
export const publishedShareStatePages = (
  ['empty', 'denied', 'readonly', 'readback-denied'] as const
).map((state) =>
  definePage({
    id: 'published-shares-' + state,
    title: 'Published Shares',
    native: true,
    presentation,
  }),
);
