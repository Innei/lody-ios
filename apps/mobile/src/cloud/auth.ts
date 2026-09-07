import { t } from '../i18n/index.ts';

// Public production endpoints observed in the official Lody web client.
export const AUTH_ORIGIN = 'https://backend.lody.ai';
export const DEVICE_CLIENT_ID = 'lody-cli';
export type User = { id: string; name: string; email: string };
export type Workspace = { id: string; name: string; slug: string | null };
export type DeviceCode = {
  device_code: string;
  user_code: string;
  verification_uri_complete: string;
  expires_in: number;
  interval: number;
};
export class AuthError extends Error {}
export function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new Error(t('auth.error.invalidResponse'));
  return value as Record<string, unknown>;
}
export function requiredString(value: unknown): string {
  if (typeof value !== 'string' || !value.trim())
    throw new Error(t('auth.error.missingFields'));
  return value;
}
export async function authRequest(
  path: string,
  options: { token?: string; body?: unknown; signal?: AbortSignal } = {},
) {
  const response = await fetch(`${AUTH_ORIGIN}/api/auth${path}`, {
    method: options.body === undefined ? 'GET' : 'POST',
    credentials: 'omit',
    signal: options.signal,
    headers: {
      'Content-Type': 'application/json',
      ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
    },
    ...(options.body === undefined
      ? {}
      : { body: JSON.stringify(options.body) }),
  });
  const data: unknown = await response.json();
  if (response.status === 401) throw new AuthError(t('auth.error.expired'));
  if (!response.ok && path !== '/device/token')
    throw new Error(t('auth.error.requestFailed', { status: response.status }));
  return data;
}
export async function requestDeviceCode(
  signal?: AbortSignal,
): Promise<DeviceCode> {
  const data = record(
    await authRequest('/device/code', {
      body: { client_id: DEVICE_CLIENT_ID },
      signal,
    }),
  );
  const url = new URL(requiredString(data.verification_uri_complete));
  if (
    url.protocol !== 'https:' ||
    !['https://lody.ai', AUTH_ORIGIN].includes(url.origin) ||
    url.username ||
    url.password
  )
    throw new Error(t('auth.error.invalidAuthorizeUrl'));
  if (
    typeof data.expires_in !== 'number' ||
    !Number.isFinite(data.expires_in) ||
    data.expires_in <= 0 ||
    typeof data.interval !== 'number' ||
    !Number.isFinite(data.interval) ||
    data.interval <= 0
  )
    throw new Error(t('auth.error.invalidExpiry'));
  // The auth site redirects to this official web UI; match the CLI's direct device-page link.
  url.hostname = 'lody.ai';
  return {
    device_code: requiredString(data.device_code),
    user_code: requiredString(data.user_code),
    verification_uri_complete: url.href,
    expires_in: data.expires_in,
    interval: data.interval,
  };
}
export function wait(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal.aborted) throw new Error(t('common.cancelled'));
    const abort = () => {
      clearTimeout(timer);
      reject(new Error(t('auth.error.cancelledSignIn')));
    };
    const timer = setTimeout(() => {
      signal.removeEventListener('abort', abort);
      resolve();
    }, ms);
    signal.addEventListener('abort', abort, { once: true });
  });
}
export async function pollDeviceToken(
  code: DeviceCode,
  signal: AbortSignal,
  dependencies = { request: authRequest, wait, now: Date.now },
): Promise<string> {
  let interval = code.interval * 1000;
  const deadline = dependencies.now() + code.expires_in * 1000;
  while (dependencies.now() < deadline) {
    await dependencies.wait(
      Math.min(interval, deadline - dependencies.now()),
      signal,
    );
    if (signal.aborted) throw new Error(t('common.cancelled'));
    if (dependencies.now() >= deadline) break;
    const data = record(
      await dependencies.request('/device/token', {
        body: {
          client_id: DEVICE_CLIENT_ID,
          device_code: code.device_code,
          grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
        },
        signal,
      }),
    );
    if (typeof data.access_token === 'string' && data.access_token)
      return data.access_token;
    if (data.error === 'authorization_pending') continue;
    if (data.error === 'slow_down') {
      interval += 5000;
      continue;
    }
    if (data.error === 'access_denied')
      throw new Error(t('auth.error.accessDenied'));
    if (data.error === 'expired_token') break;
    throw new Error(t('auth.error.deviceAuthFailed'));
  }
  throw new Error(t('auth.error.codeExpired'));
}
export async function getAccount(
  token: string,
  signal?: AbortSignal,
): Promise<{ user: User; workspaces: Workspace[] }> {
  const session = await authRequest('/get-session', { token, signal });
  if (session === null) throw new AuthError(t('auth.error.expired'));
  const user = record(record(session).user);
  const list = await authRequest('/organization/list', { token, signal });
  if (!Array.isArray(list))
    throw new Error(t('auth.error.invalidWorkspaceList'));
  return {
    user: {
      id: requiredString(user.id),
      email: requiredString(user.email),
      name:
        typeof user.name === 'string' ? user.name : requiredString(user.email),
    },
    workspaces: list.map((value) => {
      const item = record(value);
      return {
        id: requiredString(item.id),
        name: requiredString(item.name),
        slug: typeof item.slug === 'string' ? item.slug : null,
      };
    }),
  };
}
export async function getStreamsGrant(
  token: string,
  workspaceId: string,
  signal?: AbortSignal,
) {
  const response = await fetch(`${AUTH_ORIGIN}/api/loro-streams/token`, {
    method: 'POST',
    credentials: 'omit',
    signal,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ workspaceId }),
  });
  if (response.status === 401) throw new AuthError(t('auth.error.expired'));
  if (!response.ok)
    throw new Error(
      t('auth.error.workspaceUnavailable', { status: response.status }),
    );
  const grant = record(await response.json());
  const url = new URL(requiredString(grant.gatewayBaseUrl));
  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    url.search ||
    url.hash
  )
    throw new Error(t('auth.error.invalidStreamsUrl'));
  return {
    token: requiredString(grant.token),
    gatewayBaseUrl: url.href.replace(/\/$/, ''),
  };
}
