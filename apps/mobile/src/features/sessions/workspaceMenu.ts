import type { HeaderBarButtonItemMenuAction } from 'react-native-screens';
import { t } from '../../lib/i18n/index.ts';

export function workspaceMenuActions({
  openChanges,
  simulator,
}: {
  openChanges?: () => void;
  simulator: {
    menuItem: { title: string; subtitle?: string; symbol: string } | undefined;
    open: () => Promise<void>;
  };
}): HeaderBarButtonItemMenuAction[] {
  const actions: HeaderBarButtonItemMenuAction[] = [];
  if (openChanges)
    actions.push({
      type: 'action',
      title: t('workspaceChanges.title'),
      icon: { type: 'sfSymbol', name: 'plus.forwardslash.minus' },
      onPress: openChanges,
    });
  if (simulator.menuItem)
    actions.push({
      type: 'action',
      title: simulator.menuItem.title,
      subtitle: simulator.menuItem.subtitle,
      icon: { type: 'sfSymbol', name: simulator.menuItem.symbol },
      onPress: () => void simulator.open(),
    });
  return actions;
}
