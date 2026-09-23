import { useState } from 'react';
import { NativeGroupedList, type NativeListSection } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import type { Capability, ConfigOption } from '@/models/send';
import { effortsFor, extraConfigOptions } from '@/cloud/send/capability';
import type { ModelChoice } from '../models/send.ts';
import { t } from '../lib/i18n/index.ts';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

export type { ModelChoice } from '../models/send.ts';

type Params = {
  capability: Capability;
  value: ModelChoice;
  /** Params live in memory, so the screen reports every pick as it happens. */
  onChange: (next: ModelChoice) => void;
  choiceForModel: (modelId?: string) => ModelChoice;
};

const DEFAULT = 'lody:default';
const permissionOption = (option: ConfigOption) =>
  option.category === '_permission' || option.id === 'permission_mode';
const configRowId = (id: string, value: string) => `config:${id}:${value}`;

function configTitle(option: ConfigOption) {
  const titles = {
    permission_mode: 'model.tab.permission',
    'fast-mode': 'model.config.fast',
    fast: 'model.config.fast',
    collaboration_mode: 'model.config.collaboration',
    agent_preset: 'model.config.preset',
  } as const;
  const key = titles[option.id as keyof typeof titles];
  return key ? t(key) : option.name;
}

function configValueTitle(option: ConfigOption, id: string) {
  if (permissionOption(option)) {
    const labels = {
      ask: 'model.permission.ask',
      auto: 'model.permission.auto',
      'always-approve': 'model.permission.alwaysApprove',
    } as const;
    const key = labels[id as keyof typeof labels];
    if (key) return t(key);
  }
  return option.options.find((item) => item.id === id)?.name ?? id;
}

/**
 * Whether this agent offers more than models. Derived from the capability rather
 * than the current pick, so tabs never appear or vanish mid-selection.
 */
export function hasModelTabs(capability: Capability) {
  return (
    capability.modes.length > 0 ||
    Object.keys(capability.reasoningEfforts).length > 0 ||
    effortsFor(capability).length > 0 ||
    extraConfigOptions(capability).length > 0
  );
}

export function modelSummary(capability: Capability, value: ModelChoice) {
  const model = capability.models.find((m) => m.id === value.modelId);
  const mode = capability.modes.find((m) => m.id === value.modeId);
  const extras = extraConfigOptions(capability).flatMap((option) => {
    const selected = value.configOptionValues?.[option.id];
    if (selected === undefined) return [];
    if (typeof selected === 'boolean')
      return [
        `${configTitle(option)}: ${t(selected ? 'model.config.on' : 'model.config.off')}`,
      ];
    return [configValueTitle(option, selected)];
  });
  return [
    model?.name ?? t('model.default'),
    value.effort,
    mode?.name,
    ...extras,
  ]
    .filter(Boolean)
    .join(' · ');
}

function View() {
  const { params } = usePageRuntime<Params>();
  const colors = usePalette();
  const [value, setValue] = useState(params.value);
  const { capability } = params;
  const efforts = effortsFor(capability, value.modelId);
  const extras = extraConfigOptions(capability);
  const permissions = extras.filter(permissionOption);
  const otherOptions = extras.filter((option) => !permissionOption(option));

  const tabs = [{ id: 'model', title: t('model.tab.model') }];
  if (efforts.length) tabs.push({ id: 'effort', title: t('model.tab.effort') });
  if (capability.modes.length)
    tabs.push({ id: 'mode', title: t('model.tab.mode') });
  if (permissions.length)
    tabs.push({ id: 'permission', title: t('model.tab.permission') });
  if (otherOptions.length)
    tabs.push({ id: 'more', title: t('model.tab.more') });
  const [tab, setTab] = useState('model');
  const active = tabs.find((item) => item.id === tab)?.id ?? 'model';

  function apply(next: ModelChoice) {
    setValue(next);
    params.onChange(next);
  }

  function applyConfig(id: string, selected?: string | boolean) {
    const configOptionValues = { ...value.configOptionValues };
    if (selected === undefined) delete configOptionValues[id];
    else configOptionValues[id] = selected;
    apply({ ...value, configOptionValues });
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

  let sections: NativeListSection[] = [
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
  const visibleOptions = active === 'permission' ? permissions : otherOptions;
  if (active === 'permission' || active === 'more') {
    sections = visibleOptions.map((option) => {
      const selected = value.configOptionValues?.[option.id];
      const rows: NativeListSection['rows'] = [
        {
          id: configRowId(option.id, DEFAULT),
          title: t('model.useDefault'),
          image: selected === undefined ? 'checkmark' : undefined,
          action: true,
        },
      ];
      if (option.type === 'boolean') {
        rows.push({
          id: option.id,
          title: configTitle(option),
          toggle: (selected ?? option.currentValue) === true,
          action: true,
        });
      } else {
        rows.push(
          ...option.options.map((item) => ({
            id: configRowId(option.id, item.id),
            title: configValueTitle(option, item.id),
            subtitle: item.description,
            image: selected === item.id ? 'checkmark' : undefined,
            action: true,
          })),
        );
      }
      return {
        id: option.id,
        header: configTitle(option),
        footer: option.description,
        rows,
      };
    });
  }

  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      transparent
      sections={sections}
      segments={tabs.length > 1 ? tabs.map((entry) => entry.title) : undefined}
      selectedSegment={tabs.findIndex((item) => item.id === active)}
      onSegmentChange={({ nativeEvent }) =>
        setTab(tabs[nativeEvent.index]?.id ?? 'model')
      }
      placeholder=""
      onRowToggle={({ nativeEvent }) =>
        applyConfig(nativeEvent.id, nativeEvent.value)
      }
      onRowPress={({ nativeEvent }) => {
        if (active === 'permission' || active === 'more') {
          for (const option of visibleOptions) {
            if (nativeEvent.id === configRowId(option.id, DEFAULT)) {
              applyConfig(option.id);
              return;
            }
            const picked = option.options.find(
              (item) => nativeEvent.id === configRowId(option.id, item.id),
            );
            if (picked) {
              applyConfig(option.id, picked.id);
              return;
            }
          }
          return;
        }
        const picked = nativeEvent.id === DEFAULT ? undefined : nativeEvent.id;
        if (active === 'model') apply(params.choiceForModel(picked));
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
    throw new Error('Open this page from the new session screen');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
