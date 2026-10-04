import { initialQuickRepliesJSON, saveQuickReplies } from '@lody-ios/kit';
import {
  createContext,
  use,
  useCallback,
  useMemo,
  useState,
  type PropsWithChildren,
} from 'react';
import type { QuickReply } from '@/models/settings';
import { t } from '@/lib/i18n';
import { showToast } from '@/ui/toast';
import { parseQuickReplies } from './quickReplies';

export function defaultQuickReplies(): QuickReply[] {
  return (['continue', 'review', 'commit-push'] as const).map((id) => ({
    id,
    label: t(`settings.quickReplies.defaults.${id}.label`),
    message: t(`settings.quickReplies.defaults.${id}.message`),
  }));
}

const QuickRepliesContext = createContext<{
  quickReplies: QuickReply[];
  setQuickReplies: (items: QuickReply[]) => boolean;
} | null>(null);

export function QuickRepliesProvider({ children }: PropsWithChildren) {
  const [quickReplies, setValue] = useState(
    () => parseQuickReplies(initialQuickRepliesJSON) ?? defaultQuickReplies(),
  );
  const setQuickReplies = useCallback((items: QuickReply[]) => {
    try {
      saveQuickReplies(JSON.stringify(items));
      setValue(items);
      return true;
    } catch {
      showToast(t('settings.quickReplies.saveFailed'), 'error');
      return false;
    }
  }, []);
  const value = useMemo(
    () => ({ quickReplies, setQuickReplies }),
    [quickReplies, setQuickReplies],
  );
  return <QuickRepliesContext value={value}>{children}</QuickRepliesContext>;
}

export function useQuickReplies() {
  const value = use(QuickRepliesContext);
  if (!value)
    throw new Error('useQuickReplies must be used inside QuickRepliesProvider');
  return value;
}
