import {
  createContext,
  use,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { StyleSheet } from 'react-native';
import type { ScreenStackHeaderConfigProps } from 'react-native-screens';
import {
  ScreenStack,
  ScreenStackHeaderRightView,
  ScreenStackItem,
} from 'react-native-screens';
import { NativeCloseButton } from '@lody-ios/kit';

import type {
  PageDefinitionBase,
  PageFinish,
  PagePresentationOptions,
  PageRuntime,
  PushPage,
} from './page';
import { PageRuntimeProvider } from './page';
import type { PresentationResult } from './presentationStore';
import { present, type PresentationSession } from './presentationStore';
import { t } from '../i18n/index.ts';

type HeaderItems = ScreenStackHeaderConfigProps['headerRightBarButtonItems'];
const SheetHeader = createContext<((items: HeaderItems) => void) | null>(null);

/** Set actual UINavigationItem buttons on the owning sheet level. */
export function useSheetHeader(items: HeaderItems) {
  const setItems = use(SheetHeader);
  useEffect(() => {
    setItems?.(items);
    return () => setItems?.(undefined);
  }, [setItems, items]);
}

type Level = {
  key: number;
  page: PageDefinitionBase;
  params: unknown;
  presentation: PagePresentationOptions;
  settle: (result: PresentationResult<unknown>) => void;
};

function headerConfig(
  page: PageDefinitionBase,
  presentation: PagePresentationOptions,
  right?: React.ReactNode,
): ScreenStackHeaderConfigProps {
  return {
    title: presentation.title ?? page.title,
    hidden: !presentation.headerShown,
    topInsetEnabled: false,
    backButtonDisplayMode: 'minimal',
    translucent: true,
    hideShadow: true,
    backgroundColor: 'transparent',
    blurEffect:
      presentation.headerVariant === 'glass' ? 'systemChromeMaterial' : 'none',
    children: right ? (
      <ScreenStackHeaderRightView>{right}</ScreenStackHeaderRightView>
    ) : undefined,
  };
}

/**
 * A presented page owns a native stack of its own, so pushing inside a sheet
 * stays inside that sheet. Pushing through the root router would land the new
 * screen in the navigation controller that presented the sheet — behind it.
 */
export function SheetStack({
  session,
  runtime,
}: {
  session: PresentationSession;
  runtime: PageRuntime<unknown, unknown>;
}) {
  const [headerItems, setHeaderItems] = useState<HeaderItems>();
  const [levels, setLevels] = useState<readonly Level[]>([]);
  const nextKey = useRef(1);
  const pendingLevels = useRef(levels);
  pendingLevels.current = levels;
  useEffect(
    () => () => {
      for (const level of pendingLevels.current)
        level.settle({ status: 'cancelled' });
    },
    [],
  );

  const drop = useCallback(
    (key: number, result: PresentationResult<unknown>) => {
      setLevels((current) => {
        const level = current.find((entry) => entry.key === key);
        if (!level) return current;
        level.settle(result);
        for (const child of current) {
          if (child.key > key) child.settle({ status: 'cancelled' });
        }
        return current.filter((entry) => entry.key < key);
      });
    },
    [],
  );

  const push = useCallback<PushPage>((page, ...args) => {
    const [params, overrides] = args as [
      unknown,
      Partial<PagePresentationOptions>?,
    ];
    const key = nextKey.current++;
    return new Promise((resolve) => {
      setLevels((current) => [
        ...current,
        {
          key,
          page: page as PageDefinitionBase,
          params,
          presentation: {
            ...(page as PageDefinitionBase).presentation,
            ...overrides,
          },
          settle: resolve as (result: PresentationResult<unknown>) => void,
        },
      ]);
    });
  }, []) as PushPage;

  const rootRuntime = useMemo(() => ({ ...runtime, push }), [runtime, push]);

  // A sheet that refuses the swipe still needs a way out, so the close button
  // does not depend on `dismissible`.
  const showClose =
    session.presentation.style !== 'push' && session.presentation.headerShown;

  return (
    <ScreenStack style={StyleSheet.absoluteFill}>
      <ScreenStackItem
        screenId={`presented-${session.id}`}
        style={StyleSheet.absoluteFill}
        headerConfig={{
          ...headerConfig(
            session.page,
            session.presentation,
            showClose && !headerItems ? (
              <NativeCloseButton
                label={t('accessibility.closeSheet', {
                  title: session.page.title,
                })}
                onPress={runtime.cancel}
                style={{ width: 30, height: 30 }}
              />
            ) : undefined,
          ),
          headerRightBarButtonItems: headerItems,
        }}
      >
        <SheetHeader value={setHeaderItems}>
          <PageRuntimeProvider value={rootRuntime}>
            <session.page.Component />
          </PageRuntimeProvider>
        </SheetHeader>
      </ScreenStackItem>
      {levels.map((level) => (
        <PushedLevel key={level.key} level={level} push={push} onDrop={drop} />
      ))}
    </ScreenStack>
  );
}

function PushedLevel({
  level,
  push,
  onDrop,
}: {
  level: Level;
  push: PushPage;
  onDrop: (key: number, result: PresentationResult<unknown>) => void;
}) {
  const [headerItems, setHeaderItems] = useState<HeaderItems>();
  const cancel = useCallback(
    () => onDrop(level.key, { status: 'cancelled' }),
    [level.key, onDrop],
  );
  const finish = useCallback(
    (value?: unknown) => onDrop(level.key, { status: 'completed', value }),
    [level.key, onDrop],
  ) as PageFinish<unknown>;
  const runtime = useMemo<PageRuntime<unknown, unknown>>(
    () => ({
      cancel,
      finish,
      params: level.params,
      present,
      push,
      source: 'presentation',
    }),
    [cancel, finish, level.params, push],
  );

  return (
    <ScreenStackItem
      screenId={`presented-level-${level.key}`}
      stackPresentation="push"
      style={StyleSheet.absoluteFill}
      headerConfig={{
        ...headerConfig(level.page, level.presentation),
        headerRightBarButtonItems: headerItems,
      }}
      gestureEnabled={level.presentation.dismissible}
      onDismissed={cancel}
    >
      <SheetHeader value={setHeaderItems}>
        <PageRuntimeProvider value={runtime}>
          <level.page.Component />
        </PageRuntimeProvider>
      </SheetHeader>
    </ScreenStackItem>
  );
}
