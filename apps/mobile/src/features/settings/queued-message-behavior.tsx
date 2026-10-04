import {
  initialQueuedMessageBehavior,
  saveQueuedMessageBehavior,
} from '@lody-ios/kit';
import {
  createContext,
  type PropsWithChildren,
  use,
  useCallback,
  useMemo,
  useState,
} from 'react';
import {
  parseQueuedMessageBehavior,
  type QueuedMessageBehavior,
} from '@/features/sessions/messageSubmitRoute';

const initial = parseQueuedMessageBehavior(initialQueuedMessageBehavior);

const QueuedMessageBehaviorContext = createContext<{
  queuedMessageBehavior: QueuedMessageBehavior;
  setQueuedMessageBehavior: (value: QueuedMessageBehavior) => void;
} | null>(null);

export function QueuedMessageBehaviorProvider({ children }: PropsWithChildren) {
  const [queuedMessageBehavior, setValue] = useState(initial);
  const setQueuedMessageBehavior = useCallback(
    (value: QueuedMessageBehavior) => {
      saveQueuedMessageBehavior(value);
      setValue(value);
    },
    [],
  );
  const value = useMemo(
    () => ({ queuedMessageBehavior, setQueuedMessageBehavior }),
    [queuedMessageBehavior, setQueuedMessageBehavior],
  );
  return (
    <QueuedMessageBehaviorContext value={value}>
      {children}
    </QueuedMessageBehaviorContext>
  );
}

export function useQueuedMessageBehavior() {
  const value = use(QueuedMessageBehaviorContext);
  if (!value)
    throw new Error(
      'useQueuedMessageBehavior must be used inside QueuedMessageBehaviorProvider',
    );
  return value;
}
