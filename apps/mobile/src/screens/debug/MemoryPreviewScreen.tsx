import { definePage } from '@/lib/presentation';

const presentation = { headerVariant: 'transparent' } as const;

export const MemoryPreviewScreen = definePage({
  id: 'memory-preview',
  title: 'Memory',
  native: true,
  presentation,
});
export const MemoryStatesPreviewScreen = definePage({
  id: 'memory-states-preview',
  title: 'Memory States',
  native: true,
  presentation,
});

export const memoryStatePages = (
  [
    'catalog_denied',
    'not_installed',
    'not_running',
    'unsupported',
    'error',
    'forbidden',
    'unknown',
    'cached',
    'empty',
  ] as const
).map((state) =>
  definePage({
    id: `memory-state-${state}`,
    title: 'Memory States',
    native: true,
    presentation,
  }),
);
