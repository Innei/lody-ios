import { useState } from 'react';
import { ActivityIndicator, Pressable, TextInput, View } from 'react-native';
import type { QuestionAnswers, QuestionMeta } from '../../models/session.ts';
import {
  questionAllowsText,
  questionAnswerKey,
} from '../../cloud/permissionQuestions.ts';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';

export function QuestionCard({
  meta,
  disabled,
  onSubmit,
}: {
  meta: QuestionMeta;
  disabled: boolean;
  onSubmit: (answers: QuestionAnswers) => void;
}) {
  const colors = usePalette();
  const [page, setPage] = useState(0);
  const [submitted, setSubmitted] = useState(false);
  const editingDisabled = disabled || submitted;
  const [drafts, setDrafts] = useState(() =>
    meta.questions.map(() => ({ labels: [] as string[], text: '' })),
  );
  const question = meta.questions[page];
  const draft = drafts[page];
  if (!question || !draft) return null;
  let instruction = t('question.freeText');
  if (question.options.length)
    instruction = t(
      question.multiSelect ? 'question.multiple' : 'question.single',
    );
  const complete = drafts.every((d) => d.text.trim() || d.labels.length);
  const update = (next: typeof draft) =>
    setDrafts((current) => current.map((d, i) => (i === page ? next : d)));
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
  return (
    <View style={{ gap: 12 }}>
      <AppText variant="meta">
        {t('question.progress', {
          current: page + 1,
          total: meta.questions.length,
        })}
      </AppText>
      <AppText variant="title">{question.header}</AppText>
      <AppText>{question.question}</AppText>
      <AppText variant="secondary">{instruction}</AppText>
      {question.options.map((option, index) => {
        const selected =
          draft.labels.includes(option.label) && !draft.text.trim();
        return (
          <Pressable
            key={index}
            testID={`question-option-${index}`}
            accessibilityRole="button"
            accessibilityLabel={[
              option.label,
              option.description,
              option.preview,
            ]
              .filter(Boolean)
              .join('. ')}
            accessibilityState={{ selected, disabled: editingDisabled }}
            disabled={editingDisabled}
            onPress={() => {
              let labels = [option.label];
              if (question.multiSelect)
                labels = selected
                  ? draft.labels.filter((l) => l !== option.label)
                  : [...draft.labels, option.label];
              update({ labels, text: '' });
            }}
            style={{
              minHeight: 44,
              padding: 14,
              borderRadius: 12,
              borderWidth: selected ? 2 : 1,
              borderColor: selected ? colors.accent : colors.separator,
              backgroundColor: colors.card,
              opacity: disabled ? 0.5 : 1,
              gap: 6,
            }}
          >
            <AppText style={{ color: selected ? colors.accent : colors.label }}>
              {selected ? '✓ ' : ''}
              {option.label}
            </AppText>
            {option.description ? (
              <AppText variant="secondary">{option.description}</AppText>
            ) : null}
            {option.preview ? (
              <AppText variant="mono" selectable>
                {option.preview}
              </AppText>
            ) : null}
          </Pressable>
        );
      })}
      {questionAllowsText(meta, question) ? (
        <TextInput
          key={page}
          testID="question-custom"
          accessibilityLabel={t('question.custom')}
          placeholder={t('question.custom')}
          placeholderTextColor={colors.secondaryLabel}
          value={draft.text}
          editable={!editingDisabled}
          secureTextEntry={question.isSecret}
          autoCorrect={!question.isSecret}
          autoCapitalize={question.isSecret ? 'none' : 'sentences'}
          multiline={!question.isSecret}
          onChangeText={(text) => update({ labels: [], text })}
          style={{
            minHeight: 48,
            padding: 12,
            color: colors.label,
            backgroundColor: colors.card,
            borderRadius: 12,
            borderWidth: 1,
            borderColor: colors.separator,
            fontSize: 17,
          }}
        />
      ) : null}
      <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
        <Button
          testID="question-previous"
          label={t('question.previous')}
          disabled={disabled || page === 0}
          onPress={() => setPage(page - 1)}
        />
        <Button
          testID="question-next"
          label={t('question.next')}
          disabled={
            disabled ||
            page === meta.questions.length - 1 ||
            (!draft.text.trim() && !draft.labels.length)
          }
          onPress={() => setPage(page + 1)}
        />
      </View>
      {disabled ? <ActivityIndicator /> : null}
      <Button
        testID="question-submit"
        label={t('question.submit')}
        variant="filled"
        disabled={disabled || !complete}
        onPress={submit}
      />
    </View>
  );
}
