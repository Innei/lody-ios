import { useEffect, useReducer, useState } from 'react';
import { runOptions } from '@lody-ios/kit';
import type {
  RunOptionsCatalog,
  RunOptionsRequest,
} from '@lody/cloud-runtime/models/run-options';

const empty: RunOptionsCatalog = { roles: [], mcpServers: [] };

export function useComposerRunOptions(
  source: (RunOptionsRequest & { sessionId?: string }) | undefined,
  fixture?: RunOptionsCatalog,
  loadOptions: (request: string) => Promise<string> = runOptions,
) {
  const scope = source ? JSON.stringify(source) : '';
  const [revision, refresh] = useReducer((value) => value + 1, 0);
  const [state, setState] = useState({
    scope: '',
    catalog: empty,
    loading: false,
    error: '',
  });
  useEffect(() => {
    if (fixture || !scope) return;
    let active = true;
    setState({ scope, catalog: empty, loading: true, error: '' });
    void loadOptions(scope)
      .then((json) => {
        if (active)
          setState({
            scope,
            catalog: JSON.parse(json),
            loading: false,
            error: '',
          });
      })
      .catch(() => {
        if (active)
          setState({
            scope,
            catalog: { ...empty, unavailable: true },
            loading: false,
            error: 'run-options-unavailable',
          });
      });
    return () => {
      active = false;
    };
  }, [scope, fixture, revision, loadOptions]);
  if (fixture) return { catalog: fixture, loading: false, error: '', refresh };
  const current =
    state.scope === scope
      ? state
      : { catalog: empty, loading: !!scope, error: '' };
  return {
    catalog: current.catalog,
    loading: current.loading,
    error: current.error,
    refresh,
  };
}
