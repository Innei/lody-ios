import { type Href, router } from 'expo-router';

import type {
  PageDefinition,
  PageDefinitionBase,
  PagePresentationOptions,
} from './page';

export type PresentationResult<TResult> =
  { status: 'cancelled' } | { status: 'completed'; value: TResult };

type PresentOptions = Partial<PagePresentationOptions> & {
  /** A native local host can render the same session without a Router modal. */
  host?: (session: PresentationSession) => void;
};

type PresentArgs<TParams> = [TParams] extends [undefined]
  ? [params?: TParams, options?: PresentOptions]
  : [params: TParams, options?: PresentOptions];

export interface PresentationSession {
  id: number;
  page: PageDefinitionBase;
  params: unknown;
  presentation: PagePresentationOptions;
}

interface StoredPresentationSession extends PresentationSession {
  resolve: (result: PresentationResult<unknown>) => void;
}

let nextId = 1;
let sessions: readonly StoredPresentationSession[] = [];

function settle(id: number, result: PresentationResult<unknown>) {
  const session = sessions.find((candidate) => candidate.id === id);
  if (!session) return false;

  sessions = sessions.filter((candidate) => candidate.id !== id);
  session.resolve(result);
  return true;
}

export function present<TParams, TResult>(
  page: PageDefinition<TParams, TResult>,
  ...args: PresentArgs<TParams>
): Promise<PresentationResult<TResult>> {
  const [params, options] = args;
  const { host, ...presentation } = options ?? {};
  const id = nextId++;

  return new Promise<PresentationResult<TResult>>((resolve) => {
    sessions = [
      ...sessions,
      {
        id,
        page,
        params,
        presentation: { ...page.presentation, ...presentation },
        resolve: (result) => resolve(result as PresentationResult<TResult>),
      },
    ];

    try {
      if (host) {
        host(getPresentationSession(id)!);
        return;
      }
      router.push({
        pathname: page.presentationPath ?? '/presented/[presentationId]',
        params: { presentationId: String(id) },
      } as Href);
    } catch (error) {
      sessions = sessions.filter((candidate) => candidate.id !== id);
      throw error;
    }
  });
}

export type PresentPage = typeof present;

export function completePresentation(id: number, value: unknown): boolean {
  return settle(id, { status: 'completed', value });
}

export function cancelPresentation(id: number): boolean {
  return settle(id, { status: 'cancelled' });
}

export function getPresentationSession(
  id: number,
): PresentationSession | undefined {
  const session = sessions.find((candidate) => candidate.id === id);
  if (!session) return undefined;

  return {
    id: session.id,
    page: session.page,
    params: session.params,
    presentation: session.presentation,
  };
}
