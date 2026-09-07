import { useState } from 'react';
import { NativeGroupedList, type NativeListSection } from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { usePalette } from '@/theme/palette';
import type { Capability } from '@/models/send';
import type { ModelChoice } from '../models/send.ts';
import { t } from '../i18n/index.ts';

export type { ModelChoice } from '../models/send.ts';

type Params = {
  capability: Capability;
  value: ModelChoice;
  /** Params live in memory, so the screen reports every pick as it happens. */
  onChange: (next: ModelChoice) => void;
};

const DEFAULT = 'lody:default';

/**
 * Whether this agent offers more than models. Derived from the capability rather
 * than the current pick, so tabs never appear or vanish mid-selection.
 */
export function hasModelTabs(capability: Capability) {
  return (
    capability.modes.length > 0 ||
    Object.keys(capability.reasoningEfforts).length > 0
  );
}

export function modelSummary(capability: Capability, value: ModelChoice) {
  const model = capability.models.find((m) => m.id === value.modelId);
  const mode = capability.modes.find((m) => m.id === value.modeId);
  return [model?.name ?? t('model.default'), value.effort, mode?.name]
    .filter(Boolean)
    .join(' · ');
}

function View() {
  const { params } = usePageRuntime<Params>();
  const colors = usePalette();
  const [value, setValue] = useState(params.value);
  const { capability } = params;
  const efforts = value.modelId
    ? (capability.reasoningEfforts[value.modelId] ?? [])
    : [];

  const tabs = hasModelTabs(capability)
    ? [
        { id: 'model', title: t('model.tab.model') },
        ...(efforts.length
          ? [{ id: 'effort', title: t('model.tab.effort') }]
          : []),
        ...(capability.modes.length
          ? [{ id: 'mode', title: t('model.tab.mode') }]
          : []),
      ]
    : [{ id: 'model', title: t('model.tab.model') }];
  const [tab, setTab] = useState(0);
  const active = tabs[Math.min(tab, tabs.length - 1)]!.id;

  function apply(next: ModelChoice) {
    setValue(next);
    params.onChange(next);
  }

  let rows: {
    id: string;
    title: string;
    subtitle?: string;
    selected: boolean;
  }[];
  if (active === 'model') {
    rows = [
      { id: DEFAULT, title: t('model.useDefault'), selected: !value.modelId },
      ...capability.models.map((model) => ({
        id: model.id,
        title: model.name,
        subtitle: model.description,
        selected: model.id === value.modelId,
      })),
    ];
  } else if (active === 'effort') {
    rows = [
      { id: DEFAULT, title: t('model.useDefault'), selected: !value.effort },
      ...efforts.map((effort) => ({
        id: effort,
        title: effort,
        selected: effort === value.effort,
      })),
    ];
  } else {
    rows = [
      { id: DEFAULT, title: t('model.useDefault'), selected: !value.modeId },
      ...capability.modes.map((mode) => ({
        id: mode.id,
        title: mode.name,
        subtitle: mode.description,
        selected: mode.id === value.modeId,
      })),
    ];
  }

  const footers = {
    effort: t('model.footer.effort'),
    mode: t('model.footer.mode'),
    model: t('model.footer.model'),
  };

  const sections: NativeListSection[] = [
    {
      id: active,
      footer: footers[active as keyof typeof footers] ?? footers.model,
      rows: rows.map((row) => ({
        id: row.id,
        title: row.title,
        subtitle: row.subtitle,
        image: row.selected ? 'checkmark' : undefined,
        action: true,
      })),
    },
  ];

  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      transparent
      sections={sections}
      segments={tabs.length > 1 ? tabs.map((entry) => entry.title) : undefined}
      selectedSegment={Math.min(tab, tabs.length - 1)}
      onSegmentChange={({ nativeEvent }) => setTab(nativeEvent.index)}
      placeholder=""
      onRowPress={({ nativeEvent }) => {
        const picked = nativeEvent.id === DEFAULT ? undefined : nativeEvent.id;
        if (active === 'model')
          // Efforts are model-specific, so a stale one must not survive.
          apply({ ...value, modelId: picked, effort: undefined });
        else if (active === 'effort') apply({ ...value, effort: picked });
        else apply({ ...value, modeId: picked });
      }}
    />
  );
}

export const ModelScreen = definePage<Params>({
  id: 'model',
  title: t('model.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('请从新建会话打开');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
