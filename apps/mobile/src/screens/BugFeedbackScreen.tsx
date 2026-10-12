import { useEffect, useRef, useState } from 'react';
import {
  NativeGroupedList,
  type FeedbackEnvironment,
  type NativeListSection,
} from '@lody-ios/kit';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { t } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import {
  emptyFeedbackDraft,
  feedbackEnvironmentText,
  scrubFeedbackDiagnostics,
  type FeedbackDraft,
  type FeedbackField,
} from '@/features/feedback/report';
import {
  feedbackService,
  type FeedbackService,
} from '@/features/feedback/service';
import { BugFeedbackPreviewScreen } from './BugFeedbackPreviewScreen';
import { FeedbackTextScreen } from './FeedbackTextScreen';

type Params = { service?: FeedbackService };
const fieldTitles = {
  description: 'feedback.description',
  steps: 'feedback.steps',
  expected: 'feedback.expected',
  actual: 'feedback.actual',
  diagnostics: 'feedback.diagnostics',
} as const;

function Content() {
  const { params, push } = usePageRuntime<Params>();
  const service = params.service ?? feedbackService;
  const colors = usePalette();
  const [draft, setDraft] = useState<FeedbackDraft>(emptyFeedbackDraft);
  const [environment, setEnvironment] = useState<FeedbackEnvironment>({
    systemVersion: '',
    deviceModel: '',
  });
  const [loaded, setLoaded] = useState(false);
  const [revision, setRevision] = useState(0);
  const [status, setStatus] = useState('');
  const [busy, setBusy] = useState(false);
  const pending = useRef(false);

  useEffect(() => {
    let active = true;
    setLoaded(false);
    void Promise.allSettled([service.load(), service.environment()]).then(
      ([stored, info]) => {
        if (!active) return;
        if (stored.status === 'fulfilled') {
          setDraft(stored.value);
          setLoaded(true);
        } else setStatus(t('feedback.loadFailed'));
        if (info.status === 'fulfilled') setEnvironment(info.value);
      },
    );
    return () => {
      active = false;
    };
  }, [service, revision]);

  async function save(next: FeedbackDraft) {
    setDraft(next);
    try {
      await service.save(next);
    } catch {
      setStatus(t('feedback.saveFailed'));
      throw new Error(t('feedback.saveFailed'));
    }
  }

  async function perform(action: () => Promise<void>, failure: string) {
    if (pending.current || !loaded) return;
    pending.current = true;
    setBusy(true);
    setStatus('');
    try {
      await action();
    } catch {
      setStatus(failure);
    } finally {
      pending.current = false;
      setBusy(false);
    }
  }

  async function edit(field: FeedbackField) {
    const result = await push(
      FeedbackTextScreen,
      {
        value: draft[field] ?? '',
        title: t(fieldTitles[field]),
        diagnostics: field === 'diagnostics',
      },
      { title: t(fieldTitles[field]) },
    );
    if (result.status === 'completed')
      await perform(
        () => save({ ...draft, [field]: result.value }),
        t('feedback.saveFailed'),
      );
  }

  function preview() {
    if (!loaded || busy || !draft.description.trim()) return;
    void push(BugFeedbackPreviewScreen, {
      draft,
      environment,
      service,
      update: save,
    });
  }
  const enabled = loaded && !busy;
  const sections: NativeListSection[] = [
    {
      id: 'feedback-fields',
      footer: t('feedback.draftHint'),
      rows: (['description', 'steps', 'expected', 'actual'] as const).map(
        (field) => ({
          id: `feedback-${field}`,
          title: t(fieldTitles[field]),
          subtitle: draft[field].trim() || t('feedback.empty'),
          action: enabled,
          disclosure: true,
          navigates: true,
        }),
      ),
    },
    {
      id: 'feedback-environment',
      header: t('feedback.environment'),
      footer: t('feedback.environmentHint'),
      rows: [
        {
          id: 'feedback-device',
          title: t('feedback.environment'),
          subtitle:
            feedbackEnvironmentText(environment) ||
            t('feedback.unknownEnvironment'),
          wrapSubtitle: true,
        },
      ],
    },
    {
      id: 'feedback-attachments',
      header: t('feedback.attachments'),
      footer: t('feedback.screenshotHint'),
      rows: [
        ...draft.screenshots.map((item, index) => ({
          id: `feedback-image-${index}`,
          title: t('feedback.screenshot', { index: index + 1 }),
          image: item.uri,
          action: enabled,
          disclosure: true,
          menuActions: [
            {
              id: 'remove',
              title: t('feedback.removeScreenshot'),
              destructive: true,
            },
          ],
        })),
        {
          id: 'feedback-add-image',
          title: t('feedback.addScreenshot'),
          subtitle: t('feedback.screenshotLimit'),
          image: 'photo.badge.plus',
          action: enabled && draft.screenshots.length < 4,
        },
        {
          id: 'feedback-diagnostics',
          title: t('feedback.diagnostics'),
          subtitle: draft.diagnostics ?? t('feedback.diagnosticsOff'),
          image: 'doc.text',
          action: enabled,
          disclosure: true,
          navigates: draft.diagnostics !== undefined,
          menuActions:
            draft.diagnostics !== undefined
              ? [
                  {
                    id: 'remove',
                    title: t('feedback.removeDiagnostics'),
                    destructive: true,
                  },
                ]
              : [],
        },
      ],
    },
    {
      id: 'feedback-actions',
      footer: t('feedback.publicWarning'),
      rows: [
        {
          id: 'feedback-preview',
          title: t('feedback.preview'),
          image: 'doc.text.magnifyingglass',
          action: enabled && !!draft.description.trim(),
          disclosure: true,
          navigates: true,
        },
      ],
    },
  ];
  if (status || !loaded)
    sections.unshift({
      id: 'feedback-status',
      rows: [
        {
          id: 'feedback-message',
          title: status || t('common.loading'),
          subtitle: !loaded && status ? t('common.retry') : undefined,
          action: !loaded && !!status,
        },
      ],
    });

  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={sections}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'feedback-message') {
          setStatus('');
          setRevision((value) => value + 1);
        }
        for (const field of [
          'description',
          'steps',
          'expected',
          'actual',
        ] as const)
          if (id === `feedback-${field}`) void edit(field);
        if (id === 'feedback-preview') preview();
        if (id === 'feedback-add-image')
          void perform(async () => {
            const item = await service.pickScreenshot();
            if (item)
              await save({
                ...draft,
                screenshots: [...draft.screenshots, item],
              });
          }, t('feedback.imageFailed'));
        if (id.startsWith('feedback-image-')) {
          const item =
            draft.screenshots[Number(id.slice('feedback-image-'.length))];
          if (item)
            void perform(async () => {
              const updated = await service.previewScreenshot(item.uri);
              if (updated)
                await save({
                  ...draft,
                  screenshots: draft.screenshots.map((old) =>
                    old.uri === item.uri ? updated : old,
                  ),
                });
            }, t('feedback.imageFailed'));
        }
        if (id === 'feedback-diagnostics') {
          if (draft.diagnostics !== undefined) void edit('diagnostics');
          else
            void perform(async () => {
              const summary = scrubFeedbackDiagnostics(
                await service.diagnostics(),
              );
              await save({ ...draft, diagnostics: summary });
            }, t('feedback.diagnosticsFailed'));
        }
      }}
      onRowAction={({ nativeEvent: { id, actionId } }) => {
        if (actionId !== 'remove') return;
        if (id === 'feedback-diagnostics')
          void perform(
            () => save({ ...draft, diagnostics: undefined }),
            t('feedback.saveFailed'),
          );
        if (id.startsWith('feedback-image-')) {
          const item =
            draft.screenshots[Number(id.slice('feedback-image-'.length))];
          if (item)
            void perform(async () => {
              await save({
                ...draft,
                screenshots: draft.screenshots.filter(
                  (old) => old.uri !== item.uri,
                ),
              });
              await service.removeScreenshot(item.uri);
            }, t('feedback.imageFailed'));
        }
      }}
    />
  );
}

export const BugFeedbackScreen = definePage<Params>({
  id: 'bug-feedback',
  title: t('feedback.title'),
  Component: Content,
  parseRouteParams: () => {
    throw new Error('Open feedback from Settings');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
