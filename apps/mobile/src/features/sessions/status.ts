import { t, type TranslationKey } from '../../i18n/index.ts';

export type SessionState =
  'live' | 'attention' | 'failed' | 'idle' | 'done' | 'archived';

const states: Record<string, SessionState> = {
  running: 'live',
  initializing: 'live',
  processing: 'live',
  requestPermission: 'attention',
  waiting: 'attention',
  error: 'failed',
  idle: 'idle',
  pending: 'idle',
  completed: 'done',
};

export function sessionState(
  status: string,
  archived = false,
  awaiting = false,
): SessionState {
  if (archived) return 'archived';
  const state = states[status] ?? 'idle';
  return awaiting && state !== 'live' ? 'attention' : state;
}

const agentNames: Record<string, string> = {
  claude: 'Claude Code',
  codex: 'Codex',
  kimi: 'Kimi Code',
  'kimi-code': 'Kimi Code',
  opencode: 'OpenCode',
};

export function agentName(agentType = '') {
  return agentNames[agentType] ?? agentType;
}

const stateKeys: Record<SessionState, TranslationKey> = {
  live: 'session.state.live',
  attention: 'session.state.attention',
  failed: 'session.state.failed',
  idle: 'session.state.idle',
  done: 'session.state.done',
  archived: 'session.state.archived',
};

export function stateLabel(state: SessionState) {
  return t(stateKeys[state]);
}

export function sessionStatus(status: string) {
  return stateLabel(sessionState(status));
}

export const stateSymbol: Record<SessionState, string> = {
  live: 'circle.fill',
  attention: 'exclamationmark.circle.fill',
  failed: 'xmark.octagon.fill',
  idle: 'circle',
  done: 'checkmark',
  archived: 'archivebox',
};

/** Accent carries "live" only; every other state uses a system semantic color. */
const tints: Record<SessionState, string> = {
  live: 'accent',
  attention: 'warning',
  failed: 'danger',
  archived: 'tertiary',
  idle: 'secondary',
  done: 'secondary',
};
export function stateTint(state: SessionState, accent: string) {
  return state === 'live' ? accent : tints[state];
}

/** Row subtitle: state word only where it earns the space, then project and time. */
export function stateSubtitle(state: SessionState, ...rest: string[]) {
  const lead = state === 'done' ? [] : [stateLabel(state)];
  return [...lead, ...rest.filter(Boolean)].join(' · ');
}
