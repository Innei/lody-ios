import { useMemo, useState } from 'react';
import {
  NativeGroupedList,
  NativeNavigationHeader,
  type NativeListRow,
  type NativeListSection,
} from '@lody-ios/kit';
import type {
  ScheduleRule,
  ScheduleTrigger,
} from '@lody/cloud-runtime/models/schedules';
import {
  instantToZonedLocalInput,
  previewSchedule,
  triggerToRule,
  zonedLocalInputToInstant,
} from '@lody/cloud-runtime/protocol/schedule-time';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import {
  copy,
  dateLabel,
  ruleKinds,
  ruleTitle,
  scheduleRuleCandidate,
} from '@/features/schedules/model';
import { ScheduleFieldScreen } from './ScheduleFieldScreen';

type Params = { trigger: ScheduleTrigger; timeZone: string };
function View() {
  const { params, finish, present } = usePageRuntime<Params, ScheduleTrigger>(),
    colors = usePalette();
  const original = useMemo(
    () => triggerToRule(params.trigger, params.timeZone),
    [params.trigger, params.timeZone],
  );
  const [rule, setRule] = useState<ScheduleRule | null>(original);
  const trigger = scheduleRuleCandidate(params.trigger, rule, params.timeZone);
  const error = trigger ? '' : copy('schedules.invalidTime');
  const preview = trigger ? previewSchedule(trigger, 0, Date.now()) : [];
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        title: copy('common.done'),
        accessibilityLabel: copy('common.done'),
        disabled: !trigger,
        onPress: () => {
          if (trigger) finish(trigger);
        },
      },
    ],
    [finish, trigger],
  );
  const rows: NativeListRow[] = [
    {
      id: 'rule-kind',
      title: copy('schedules.frequency'),
      value: rule ? ruleTitle(rule.kind) : copy('schedules.rule.custom'),
      action: true,
      options: ruleKinds.map((kind) => ({
        id: kind,
        title: ruleTitle(kind),
        selected: rule?.kind === kind,
      })),
    },
  ];
  if (rule?.kind === 'minutes' || rule?.kind === 'hours')
    rows.push({
      id: 'every',
      title: copy('schedules.every'),
      value: String(rule.every),
      action: true,
      disclosure: true,
    });
  if (
    rule &&
    ['daily', 'weekdays', 'weekly', 'monthly'].includes(rule.kind) &&
    'hour' in rule
  )
    rows.push({
      id: 'time',
      title: copy('schedules.time'),
      value: `${String(rule.hour).padStart(2, '0')}:${String(rule.minute).padStart(2, '0')}`,
      action: true,
      disclosure: true,
    });
  if (rule?.kind === 'once')
    rows.push({
      id: 'once',
      title: copy('schedules.onceDate'),
      value: Number.isFinite(Date.parse(rule.at))
        ? instantToZonedLocalInput(
            Date.parse(rule.at),
            params.timeZone,
          ).replace('T', ' ')
        : copy('schedules.invalidTime'),
      action: true,
      disclosure: true,
    });
  rows.push({
    id: 'zone',
    title: copy('schedules.timeZone'),
    value: params.timeZone,
  });
  const sections: NativeListSection[] = [
    { id: 'rule', footer: copy('schedules.machineClock'), rows },
  ];
  if (rule?.kind === 'weekly')
    sections.push({
      id: 'weekdays',
      header: copy('schedules.days'),
      rows: Array.from({ length: 7 }, (_, day) => ({
        id: `weekday:${day}`,
        title: copy(`schedules.weekday.${day}`),
        toggle: rule.weekdays.includes(day),
        action: true,
      })),
    });
  if (rule?.kind === 'monthly')
    sections.push({
      id: 'monthdays',
      header: copy('schedules.days'),
      footer: copy('schedules.monthDaysHint'),
      rows: Array.from({ length: 31 }, (_, index) => ({
        id: `monthday:${index + 1}`,
        title: String(index + 1),
        toggle: rule.days.includes(index + 1),
        action: true,
      })),
    });
  sections.push({
    id: 'preview',
    header: copy('schedules.nextRuns'),
    rows: error
      ? [
          {
            id: 'schedule-rule-error',
            title: error,
            image: 'exclamationmark.triangle',
            imageTint: 'warning',
          },
        ]
      : preview.map((ms, index) => ({
          id: `schedule-preview:${index}`,
          title: dateLabel(ms, params.timeZone),
        })),
    footer:
      trigger?.kind === 'manual' ? copy('schedules.manualHint') : undefined,
  });
  function changeKind(kind: ScheduleRule['kind']) {
    let hour = 9,
      minute = 0;
    if (rule && 'hour' in rule) {
      hour = rule.hour;
      minute = rule.minute;
    }
    const time = { hour, minute, timeZone: params.timeZone };
    switch (kind) {
      case 'manual':
        setRule({ kind });
        break;
      case 'once':
        setRule({ kind, at: new Date(Date.now() + 3_600_000).toISOString() });
        break;
      case 'minutes':
        setRule({ kind, every: 15 });
        break;
      case 'hours':
        setRule({ kind, every: 1 });
        break;
      case 'weekly':
        setRule({ kind, weekdays: [1], ...time });
        break;
      case 'monthly':
        setRule({ kind, days: [1], ...time });
        break;
      default:
        setRule({ kind, ...time });
    }
  }
  async function edit(id: string) {
    if (!rule) return;
    if (id === 'every' && 'every' in rule) {
      const result = await present(ScheduleFieldScreen, {
        title: copy('schedules.every'),
        value: String(rule.every),
        keyboardType: 'number-pad',
        hint: copy('schedules.everyHint'),
      });
      if (result.status === 'completed')
        setRule({ ...rule, every: Number(result.value) });
    }
    if (id === 'time' && 'hour' in rule) {
      const result = await present(ScheduleFieldScreen, {
        title: copy('schedules.time'),
        value: `${String(rule.hour).padStart(2, '0')}:${String(rule.minute).padStart(2, '0')}`,
        keyboardType: 'numbers-and-punctuation',
        hint: copy('schedules.timeHint'),
      });
      if (result.status === 'completed') {
        const match = /^(\d{1,2}):(\d\d)$/.exec(result.value);
        setRule({
          ...rule,
          hour: match ? Number(match[1]) : NaN,
          minute: match ? Number(match[2]) : NaN,
        });
      }
    }
    if (id === 'once' && rule.kind === 'once') {
      const result = await present(ScheduleFieldScreen, {
        title: copy('schedules.onceDate'),
        value: Number.isFinite(Date.parse(rule.at))
          ? instantToZonedLocalInput(
              Date.parse(rule.at),
              params.timeZone,
            ).replace('T', ' ')
          : '',
        keyboardType: 'numbers-and-punctuation',
        hint: copy('schedules.dateHint'),
      });
      if (result.status === 'completed') {
        const instant = zonedLocalInputToInstant(
          result.value.trim().replace(' ', 'T'),
          params.timeZone,
        );
        setRule({
          kind: 'once',
          at: instant === null ? '' : new Date(instant).toISOString(),
        });
      }
    }
  }
  return (
    <>
      <NativeNavigationHeader
        title={copy('schedules.frequency')}
        items={actions}
      />
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        sections={sections}
        onRowPress={({ nativeEvent }) => void edit(nativeEvent.id)}
        onRowAction={({ nativeEvent }) => {
          if (nativeEvent.id === 'rule-kind')
            changeKind(nativeEvent.actionId as ScheduleRule['kind']);
        }}
        onRowToggle={({ nativeEvent: { id, value } }) => {
          if (rule?.kind === 'weekly' && id.startsWith('weekday:')) {
            const day = Number(id.slice(8));
            setRule({
              ...rule,
              weekdays: value
                ? [...rule.weekdays, day]
                : rule.weekdays.filter((entry) => entry !== day),
            });
          }
          if (rule?.kind === 'monthly' && id.startsWith('monthday:')) {
            const day = Number(id.slice(9));
            setRule({
              ...rule,
              days: value
                ? [...rule.days, day]
                : rule.days.filter((entry) => entry !== day),
            });
          }
        }}
      />
    </>
  );
}
export const ScheduleRuleScreen = definePage<Params, ScheduleTrigger>({
  id: 'schedule-rule',
  title: copy('schedules.frequency'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from schedule editor');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
