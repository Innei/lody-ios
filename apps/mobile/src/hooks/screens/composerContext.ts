import { ActionSheetIOS } from 'react-native';
import { t } from '../../lib/i18n/index.ts';

type Action = {
  id: string;
  title: string;
  symbol: string;
  destructive?: boolean;
};
type Chip = {
  label: string;
  symbol: string;
  state: string;
  accessibilityLabel: string;
  actions: Action[];
};
type Source = {
  chip: Chip | undefined;
  onChip: (action: string) => void;
  openTitle: (chip: Chip) => string;
};

/** The composer hosts one context chip; several resources merge into a count. */
export function composerContext(sources: Source[]) {
  const live = sources.flatMap((source) =>
    source.chip ? [{ ...source, chip: source.chip }] : [],
  );
  if (live.length < 2)
    return {
      chip: live[0]?.chip,
      onPreview: (action: string) => live[0]?.onChip(action),
    };
  const label = t('session.context.count', { count: live.length });
  return {
    chip: {
      label,
      symbol: 'square.stack',
      state: live.some((source) => source.chip.state === 'connecting')
        ? 'connecting'
        : 'ready',
      accessibilityLabel: label,
      actions: live.flatMap((source, index) =>
        source.chip.actions.map((action) => ({
          ...action,
          id: `${index}:${action.id}`,
        })),
      ),
    },
    onPreview: (action: string) => {
      if (action !== 'open') {
        const [index, id] = action.split(/:(.*)/s);
        live[Number(index)]?.onChip(id);
        return;
      }
      const options = [
        ...live.map((source) => source.openTitle(source.chip)),
        t('common.cancel'),
      ];
      ActionSheetIOS.showActionSheetWithOptions(
        { options, cancelButtonIndex: live.length },
        (index) => live[index]?.onChip('open'),
      );
    },
  };
}
