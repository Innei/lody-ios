import { use, useEffect, useState } from 'react';
import { ActivityIndicator, Alert, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import type { NativeListRow } from '@lody-ios/kit';
import type { QuestionAnswers, QuestionMeta } from '../../models/session.ts';
import {
  questionAllowsText,
  questionAnswerKey,
} from '../../cloud/permissionQuestions.ts';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { ComposerSheet } from '@/ui/ComposerSheet';
import { SheetHeaderContext } from '@/lib/presentation/SheetStack';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';

export function QuestionCard({
  meta,
  disabled,
  error,
  onSubmit,
}: {
  meta: QuestionMeta;
  disabled: boolean;
  error: string;
  onSubmit: (answers: QuestionAnswers) => void;
}) {
  const colors = usePalette();
  const setHeader = use(SheetHeaderContext);
  const [page, setPage] = useState(0);
  const [submitted, setSubmitted] = useState(false);
  const editingDisabled = disabled || submitted;
  const [drafts, setDrafts] = useState(() =>
    meta.questions.map(() => ({ labels: [] as string[], text: '' })),
  );
  const question = meta.questions[page];
  const draft = drafts[page];
  const multiple = meta.questions.length > 1;
  const title = multiple ? undefined : question?.header;
  useEffect(() => {
    setHeader?.({ right: undefined, title });
    return () => setHeader?.(undefined);
  }, [setHeader, title]);
  if (!question || !draft) return null;
  let instruction = t('question.freeText');
  if (question.options.length)
    instruction = t(
      question.multiSelect ? 'question.multiple' : 'question.single',
    );
  const answered = !!draft.text.trim() || draft.labels.length > 0;
  const complete = drafts.every((d) => d.text.trim() || d.labels.length);
  const last = page === meta.questions.length - 1;
  const update = (next: typeof draft) =>
    setDrafts((current) => current.map((d, i) => (i === page ? next : d)));
  const choose = (label: string) => {
    let labels = [label];
    if (question.multiSelect)
      labels = draft.labels.includes(label)
        ? draft.labels.filter((l) => l !== label)
        : [...draft.labels, label];
    update({ labels, text: '' });
  };
  const promptText = () =>
    Alert.prompt(
      question.header,
      question.question,
      [
        { text: t('common.cancel'), style: 'cancel' },
        {
          text: t('common.done'),
          onPress: (value?: string) =>
            update({ labels: [], text: value?.trim() ?? '' }),
        },
      ],
      question.isSecret ? 'secure-text' : 'plain-text',
      question.isSecret ? '' : draft.text,
    );
  const submit = () => {
    if (!complete || disabled) return;
    setSubmitted(true);
    const entries = meta.questions.map((q, i) => {
      const d = drafts[i]!;
      let value: string | string[] = d.text.trim();
      if (!value) value = q.multiSelect ? d.labels : d.labels[0]!;
      return [questionAnswerKey(meta.questions, i), value];
    });
    onSubmit(Object.fromEntries(entries));
  };
  const text = draft.text.trim();
  const rows: NativeListRow[] = question.options.map((option, index) => ({
    id: `question-option-${index}`,
    title: option.label,
    subtitle:
      [option.description, option.preview].filter(Boolean).join('\n') ||
      undefined,
    subtitleMono: !!option.preview,
    wrapSubtitle: true,
    action: !editingDisabled,
    selected: !text && draft.labels.includes(option.label),
  }));
  if (questionAllowsText(meta, question)) {
    let customTitle = t(
      question.options.length ? 'question.otherAnswer' : 'question.custom',
    );
    if (text) customTitle = question.isSecret ? '••••••••' : text;
    rows.push({
      id: 'question-custom',
      title: customTitle,
      subtitle: text ? t('question.custom') : undefined,
      image: 'pencil',
      action: !editingDisabled,
      selected: !!text,
    });
  }
  let primary = (
    <Button
      testID={last ? 'question-submit' : 'question-next'}
      label={last ? t('question.submit') : t('question.next')}
      variant="glass"
      radius={25}
      disabled={last ? disabled || !complete : !answered}
      onPress={last ? submit : () => setPage(page + 1)}
      style={{ minHeight: 50 }}
    />
  );
  if (disabled)
    primary = (
      <View style={{ minHeight: 50, justifyContent: 'center' }}>
        <ActivityIndicator />
      </View>
    );
  return (
    <ComposerSheet
      testID="question-list"
      accent={colors.accent}
      segments={multiple ? meta.questions.map((q) => q.header) : undefined}
      segmentsStyle="steps"
      segmentsDone={drafts.map((d) => !!d.text.trim() || d.labels.length > 0)}
      selectedSegment={page}
      onSegmentChange={({ nativeEvent }) => setPage(nativeEvent.index)}
      sections={[
        {
          id: `question-${page}`,
          header: question.question,
          headerProminent: true,
          footer: instruction,
          rows,
        },
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        if (editingDisabled) return;
        if (id === 'question-custom') promptText();
        else choose(question.options[Number(id.split('-').pop())]!.label);
      }}
    >
      <SafeAreaView
        edges={{ bottom: 'maximum' }}
        style={{ gap: 10, paddingHorizontal: 16, paddingBottom: 12 }}
      >
        {error ? (
          <AppText
            variant="meta"
            style={{ color: colors.danger, textAlign: 'center' }}
          >
            {error}
          </AppText>
        ) : null}
        {primary}
      </SafeAreaView>
    </ComposerSheet>
  );
}
