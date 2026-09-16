/** RN ScrollViewMarker and navigation adapters; native scroll owners use Swift. */
export const navigationScrollEdgeEffects = {
  top: 'soft',
  bottom: 'soft',
} as const;

export const panelScrollEdgeEffects = {
  ...navigationScrollEdgeEffects,
  left: 'hidden',
  right: 'hidden',
} as const;
