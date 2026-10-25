import type { NativeBarItem } from '@lody-ios/kit';
import { t } from '@/lib/i18n';
import { type InboxModel, inboxSorts, inboxViews } from './useInboxModel';

export function inboxFilterMenu(model: InboxModel): NativeBarItem {
  return {
    type: 'menu',
    icon: { type: 'sfSymbol', name: 'line.3.horizontal.decrease' },
    tintColor: model.colors.label,
    accessibilityLabel: t('inbox.settings.section.view'),
    menu: {
      items: [
        ...inboxViews.map((view) => ({
          type: 'action' as const,
          title: t(view.key),
          icon: { type: 'sfSymbol' as const, name: view.icon },
          state: model.mode === view.mode ? ('on' as const) : ('off' as const),
          onPress: () => model.setView(view.mode),
        })),
        {
          type: 'submenu',
          displayInline: true,
          items: inboxSorts.map((item) => ({
            type: 'action' as const,
            title: t(item.key),
            icon: { type: 'sfSymbol' as const, name: item.icon },
            state: model.sort === item.id ? ('on' as const) : ('off' as const),
            onPress: () => model.setProjectSort(item.id),
          })),
        },
      ],
    },
  };
}
