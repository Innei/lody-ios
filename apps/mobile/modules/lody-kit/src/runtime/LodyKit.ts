import { NativeModule, requireNativeModule } from 'expo';

export const createSendId = () => expo.uuidv4();

export interface RuntimeInfo {
  offlineProbe?: boolean;
  uiVerifyHome: boolean;
  uiVerifySessionSearch: boolean;
  moduleName: string;
  systemVersion: string;
}
export type InboxSearchHits = {
  projectIds: string[];
  sessions: { id: string; snippet: string | null }[];
};
export type DataRuntimeEvent = {
  sessionId?: string;
  session?: string;
  owner: string;
  generation: number;
  state: string;
  reason: string;
  acknowledgements: number;
  lastStartReason?: string;
  probeUpdates?: number;
  probeBackgroundUpdates?: number;
  backgroundTaskState?: string;
  backgroundTaskCount?: number;
};
export type AttachmentUploadProgress = {
  sessionId: string;
  sendId: string;
  attachmentId: string;
  phase: 'preparing' | 'uploading' | 'verifying' | 'complete';
  percent?: number;
};
export type NavEvent =
  | { type: 'closed' | 'focus' | 'blur'; id: number }
  | {
      type: 'open';
      page: string;
      params: string;
      options?: { title?: string; present?: boolean };
      container: number;
    }
  | {
      type: 'session';
      action: 'open' | 'share' | 'create';
      workspaceId: string;
      session?: string;
      sessionId?: string;
      projectId?: string;
      context?: 'chat';
      zoomSourceLabel?: string;
      findQuery?: string;
      catalog?: string;
    }
  | { type: 'result'; id: number; value: string }
  | {
      type: 'preview';
      id: string;
      action: string;
      fields: Record<string, unknown>;
    }
  | { type: 'callback'; id: string; page: number; name: string; value: string };
export type ShellPage = {
  id: number;
  title: string;
  style: 'push' | 'formSheet' | 'fullScreen' | 'overFullScreen' | 'pageSheet';
  animation: 'fade' | 'none' | 'slide';
  dismissible: boolean;
  headerShown: boolean;
  headerVariant: 'glass' | 'transparent';
  detents?: number[];
  grabber?: boolean;
  initialDetent?: number;
  container?: number;
  root?: boolean;
  insertAt?: number;
  native?: string;
  nativeParams?: string;
};
type Events = {
  onPreferencesChange: (event: { json: string }) => void;
  onAuthChange: (event: { json: string }) => void;
  onCatalogChange: (event: { json: string }) => void;
  onOutboxChange: (event: { key: string }) => void;
  onNav: (event: NavEvent) => void;
  onAttachmentUploadProgress: (event: AttachmentUploadProgress) => void;
  onPushClick: () => void;
  onAppActive: () => void;
  onDataRuntime: (event: DataRuntimeEvent) => void;
};
declare class LodyKitNativeModule extends NativeModule<Events> {
  verifyPushSubscription(): Promise<void>;
  setPushUser(userId: string | null): Promise<void>;
  pushStatus(): Promise<import('../notifications/notifications').PushStatus>;
  pendingPushClick(): Promise<
    import('../notifications/notifications').PushClick | null
  >;
  acknowledgePushClick(id: string): Promise<void>;
  setPushVisibleRoute(route: string): Promise<void>;
  recordPushNavigation(
    id: string,
    source: string,
    outcome: string,
    reason: string,
  ): Promise<void>;
  readLocalValue(key: string): Promise<string | null>;
  searchInbox(
    userId: string,
    workspaceId: string,
    query: string,
  ): Promise<InboxSearchHits>;
  writeLocalValue(
    key: string,
    value: string,
    generation?: number,
  ): Promise<void>;
  localStoreGeneration(): number;
  readonly runtimeInfo: RuntimeInfo;
  readonly initialInboxView: number;
  saveInboxView(index: number): void;
  readonly initialInboxProjectSort: number;
  saveInboxProjectSort(index: number): void;
  saveAccentColor(value: string): void;
  accentHex(value: string, dark: boolean): string;
  accentForegroundHex(value: string): string;
  getAppIcon(): Promise<string>;
  setAppIcon(name: string): Promise<string>;
  readonly initialLocale: string;
  saveDarkBackground(value: string): void;
  readPreferences(): string;
  resetQuickReplies(): void;
  readInboxExpansion(): Record<string, boolean>;
  saveInboxExpansion(projectId: string, expanded: boolean): void;
  readInboxPinOrder(userId: string, workspaceId: string): string[];
  saveInboxPinOrder(userId: string, workspaceId: string, ids: string[]): void;
  resetInboxPreferences(userId: string, workspaceId: string): void;
  watchSession(id: string): Promise<void>;
  prepareChatEntries(
    json: string,
  ): Promise<import('../chat/PreparedChatEntries').PreparedChatEntries>;
  unwatchSession(id: string): Promise<void>;
  ensureSession(id: string): Promise<void>;
  releaseReserve(id: string): Promise<void>;
  sessionCreationOptions(payload: string): Promise<string>;
  workspaceBillingEntitlement(
    workspaceId: string,
    userId: string,
  ): Promise<string>;
  githubPullRequest(payload: string): Promise<string>;
  shareWriteCatalog(json: string): void;
  shareWriteOptions(target: string, json: string): void;
  sharePending(): string;
  shareAdopt(id: string): string;
  shareRemove(id: string): void;
  createSession(payload: string): Promise<string>;
  archiveSession(payload: string): Promise<string>;
  deleteSession(payload: string): Promise<string>;
  pinSession(payload: string): Promise<string>;
  markSessionRead(payload: string): Promise<string>;
  renameSession(payload: string): Promise<string>;
  controlSessionTurn(payload: string): Promise<string>;
  sessionPreview(payload: string): Promise<string>;
  iosSimulatorControl(payload: string): Promise<string>;
  openPreviewBrowser(url: string): Promise<void>;
  sendSessionTurn(payload: string): Promise<string>;
  readSessionEdit(payload: string): Promise<string>;
  turnDiff(payload: string): Promise<string>;
  workspaceChanges(payload: string): Promise<string>;
  fileDiff(payload: string): Promise<string>;
  readFile(payload: string): Promise<string>;
  openFile(sessionId: string, path: string, line: number): Promise<boolean>;
  listDir(payload: string): Promise<string>;
  mentionCatalog(payload: string): Promise<string>;
  readContentText(handle: string): Promise<string | null>;
  previewContent(handle: string): Promise<void>;
  dataRuntimeStatus(): Promise<DataRuntimeEvent>;
  debugBackgroundDataRuntime(action: string): Promise<string>;
  debugHangDataRuntime(): Promise<void>;
  debugProbeSchema(): Promise<string>;
  debugRestartDataRuntime(): Promise<void>;
  selectionFeedback(): Promise<void>;
  debugReplyHaptics(
    chunksMs: number[],
    config: ReplyHapticsConfig,
  ): Promise<number>;
  cancelComposerRelay(id: string): Promise<void>;
  showToast(message: string, kind: string): void;
  setSettingsPreview(json: string): void;
  navReply(id: string, error: string): void;
  prepareSheetZoom(sourceLabel: string): void;
  dismissSheetZoom(): Promise<void>;
  copyText(text: string): void;
  showSessionBanner(title: string, kind: string): void;
  dismissSessionBanner(): void;
  readAuthState(): string;
  readCatalogState(): string;
  readCatalog(): string;
  readOutbox(userId: string, workspaceId: string): string;
  outboxInflight(sessionId: string): boolean;
  setOutboxInflight(sessionId: string, active: boolean): void;
  outboxPut(userId: string, workspaceId: string, json: string): Promise<void>;
  outboxRemove(
    userId: string,
    workspaceId: string,
    sessionId: string,
  ): Promise<void>;
  setForegroundSession(sessionId: string): Promise<void>;
  navPresent(json: string): Promise<void>;
  navClose(id: number): Promise<void>;
  navPopToRoot(): Promise<void>;
  navSetStack(ids: number[]): Promise<void>;
  debugOutboxFixture(action: string): Promise<string>;
  selectWorkspace(workspaceId: string): Promise<void>;
  refreshCatalog(): Promise<void>;
  restoreAuth(): Promise<void>;
  login(): Promise<void>;
  cancelLogin(): Promise<void>;
  logout(): Promise<void>;
  reopenAuthBrowser(): Promise<void>;
  decodeFlock(
    snapshot: string,
    updates: string[],
    mode: string,
  ): Promise<string>;
}
export const native = requireNativeModule<LodyKitNativeModule>('LodyKit');
export const runtimeInfo = native.runtimeInfo;
export const saveAccentColor = (value: string) => native.saveAccentColor(value);
export const accentForegroundHex = (value: string) =>
  native.accentForegroundHex(value);
export const accentHex = (value: string, dark: boolean) =>
  native.accentHex(value, dark);
export const readPreferencesRaw = () => native.readPreferences();
export const addPreferencesListener = (
  listener: (event: { json: string }) => void,
) => native.addListener('onPreferencesChange', listener);
export const getAppIcon = () => native.getAppIcon();
export const setAppIcon = (name: string) => native.setAppIcon(name);
export const initialLocale = native.initialLocale;
export const saveDarkBackground = (value: string) =>
  native.saveDarkBackground(value);
export const resetQuickReplies = () => native.resetQuickReplies();
export function selectionFeedback(): Promise<void> {
  return native.selectionFeedback();
}

export type ReplyHapticsConfig = {
  window: number;
  duration: number;
  interval: number;
  count: number;
  intensity: number;
  endIntensity: number;
  curve: number;
  sharpness: number;
};

export const debugReplyHaptics = (
  chunksMs: number[],
  config: ReplyHapticsConfig,
) => native.debugReplyHaptics(chunksMs, config);

export function cancelComposerRelay(id: string): Promise<void> {
  return native.cancelComposerRelay(id);
}

export function prepareSheetZoom(sourceLabel: string): void {
  native.prepareSheetZoom(sourceLabel);
}

export function dismissSheetZoom(): Promise<void> {
  return native.dismissSheetZoom();
}

export type ToastKind = 'info' | 'warning' | 'error';
export type SessionBannerKind = 'completed' | 'attention';

export const setSettingsPreview = (json: string) =>
  native.setSettingsPreview(json);
export const navReply = (id: string, error = '') => native.navReply(id, error);

/** Rendered by a dedicated UIWindow above sheets, so it is never occluded. */
export function showToast(message: string, kind: ToastKind = 'error'): void {
  native.showToast(message, kind);
}

export function copyText(text: string): void {
  native.copyText(text);
}

export function showSessionBanner(
  title: string,
  kind: SessionBannerKind,
): void {
  native.showSessionBanner(title, kind);
}

export function dismissSessionBanner(): void {
  native.dismissSessionBanner();
}

export function addAppActiveListener(listener: () => void) {
  return native.addListener('onAppActive', listener);
}

export const readAuthStateRaw = () => native.readAuthState();
export const addAuthListener = (listener: (event: { json: string }) => void) =>
  native.addListener('onAuthChange', listener);
export const restoreAuth = () => native.restoreAuth();
export const loginAuth = () => native.login();
export const cancelAuth = () => native.cancelLogin();
export const logoutAuth = () => native.logout();
export const reopenAuthBrowser = () => native.reopenAuthBrowser();
export type SessionPreviewReply = {
  url?: string;
  error?: string;
  message?: string;
};
export const sessionPreview = async (
  sessionId: string,
  action: 'create' | 'revoke' = 'create',
): Promise<SessionPreviewReply> =>
  JSON.parse(
    await native.sessionPreview(JSON.stringify({ sessionId, action })),
  );
export type IosSimulatorCommand =
  | { action: 'list' }
  | { action: 'exterior'; udid: string }
  | { action: 'start'; udid: string }
  | { action: 'status'; operationId?: string }
  | { action: 'stop'; operationId: string };
export type IosSimulatorDevice = {
  udid: string;
  name: string;
  runtime: string;
  deviceType: string;
  state: string;
  available: boolean;
  unavailableReason?: string;
  occupancy: 'available' | 'this-session' | 'other-session';
};
export type IosSimulatorPreview = {
  operationId: string;
  udid: string;
  phase: 'preparing' | 'booting' | 'connecting' | 'ready' | 'closed' | 'failed';
  transport: 'local' | 'remote';
  viewerUrl?: string;
  message?: string;
};
export type IosSimulatorReply = {
  success?: boolean;
  error?: string;
  status?: number;
  message?: string;
  capabilities?: Record<string, number>;
  devices?: IosSimulatorDevice[];
  preview?: IosSimulatorPreview;
};
export const iosSimulatorControl = async (
  workspaceId: string,
  sessionId: string,
  command: IosSimulatorCommand,
): Promise<IosSimulatorReply> =>
  JSON.parse(
    await native.iosSimulatorControl(
      JSON.stringify({ workspaceId, sessionId, command }),
    ),
  );
export const openPreviewBrowser = (url: string) =>
  native.openPreviewBrowser(url);
export const decodeFlock = (
  snapshot: string,
  updates: string[],
  mode: string,
) => native.decodeFlock(snapshot, updates, mode);

export const readCatalogStateRaw = () => native.readCatalogState();
export const readCatalogRaw = () => native.readCatalog();
export const readOutboxRaw = (userId: string, workspaceId: string) =>
  native.readOutbox(userId, workspaceId);
export const addOutboxListener = (listener: (event: { key: string }) => void) =>
  native.addListener('onOutboxChange', listener);
export const outboxPut = (userId: string, workspaceId: string, json: string) =>
  native.outboxPut(userId, workspaceId, json);
export const outboxRemove = (
  userId: string,
  workspaceId: string,
  sessionId: string,
) => native.outboxRemove(userId, workspaceId, sessionId);
export const outboxInflight = (sessionId: string) =>
  native.outboxInflight(sessionId);
export const setOutboxInflight = (sessionId: string, active: boolean) =>
  native.setOutboxInflight(sessionId, active);
export const setForegroundSession = (sessionId: string) =>
  native.setForegroundSession(sessionId);
export const navPresent = (page: ShellPage) =>
  native.navPresent(JSON.stringify(page));
export const navClose = (id: number) => native.navClose(id);
export const navPopToRoot = () => native.navPopToRoot();
export const navSetStack = (ids: number[]) => native.navSetStack(ids);
export const addNavListener = (listener: (event: NavEvent) => void) =>
  native.addListener('onNav', listener);
export const debugOutboxFixture = (action: string) =>
  native.debugOutboxFixture(action);
export const addCatalogListener = (
  listener: (event: { json: string }) => void,
) => native.addListener('onCatalogChange', listener);
export const selectWorkspace = (workspaceId: string) =>
  native.selectWorkspace(workspaceId);
export const refreshCatalog = () => native.refreshCatalog();
export const addDataRuntimeListener = (
  listener: (event: DataRuntimeEvent) => void,
) => native.addListener('onDataRuntime', listener);
export const addAttachmentUploadProgressListener = (
  listener: (event: AttachmentUploadProgress) => void,
) => native.addListener('onAttachmentUploadProgress', listener);
export const dataRuntimeStatus = () => native.dataRuntimeStatus();
export const debugHangDataRuntime = () => native.debugHangDataRuntime();
export const debugProbeSchema = () => native.debugProbeSchema();
export const debugRestartDataRuntime = () => native.debugRestartDataRuntime();

export const watchSession = (id: string) => native.watchSession(id);
export const unwatchSession = (id: string) => native.unwatchSession(id);
export const ensureSession = (id: string) => native.ensureSession(id);
export const releaseReserve = (id: string) => native.releaseReserve(id);
export const controlSessionTurn = (payload: string) =>
  native.controlSessionTurn(payload);
export const sendSessionTurn = (payload: string) =>
  native.sendSessionTurn(payload);
export const readSessionEdit = (payload: string) =>
  native.readSessionEdit(payload);
export const turnDiffRaw = (payload: string) => native.turnDiff(payload);
export const workspaceChangesRaw = (payload: string) =>
  native.workspaceChanges(payload);
export const fileDiffRaw = (payload: string) => native.fileDiff(payload);
export const readFileRaw = (payload: string) => native.readFile(payload);
export const openFile = (args: {
  sessionId: string;
  path: string;
  line?: number;
}) => native.openFile(args.sessionId, args.path, args.line ?? 0);
export const mentionCatalogRaw = (payload: string) =>
  native.mentionCatalog(payload);
export const listDirRaw = (payload: string) => native.listDir(payload);
export const readContentText = (handle: string) =>
  native.readContentText(handle);
export const previewContent = (handle: string) => native.previewContent(handle);

export const sessionCreationOptions = (payload: string) =>
  native.sessionCreationOptions(payload);
export const workspaceBillingEntitlement = (
  workspaceId: string,
  userId: string,
) => native.workspaceBillingEntitlement(workspaceId, userId);
export const githubPullRequest = (payload: string) =>
  native.githubPullRequest(payload);
export const shareWriteCatalog = (json: string) =>
  native.shareWriteCatalog(json);
export const shareWriteOptions = (target: string, json: string) =>
  native.shareWriteOptions(target, json);
export const sharePending = () => native.sharePending();
export const shareAdopt = (id: string) => native.shareAdopt(id);
export const shareRemove = (id: string) => native.shareRemove(id);
export const createSession = (payload: string) => native.createSession(payload);
export const archiveSession = (payload: string) =>
  native.archiveSession(payload);
export const deleteSession = (payload: string) => native.deleteSession(payload);
export const pinSession = (payload: string) => native.pinSession(payload);
export const markSessionRead = (payload: string) =>
  native.markSessionRead(payload);
export const renameSession = (payload: string) => native.renameSession(payload);

export const initialInboxView = [0, 1, 2].includes(native.initialInboxView)
  ? native.initialInboxView
  : 0;
export const saveInboxView = (index: number) => native.saveInboxView(index);
export const projectSorts = ['name', 'activity', 'urgency'] as const;
export const initialInboxProjectSort =
  projectSorts[native.initialInboxProjectSort] ?? 'name';
export const saveInboxProjectSort = (index: number) =>
  native.saveInboxProjectSort(index);
export const readInboxExpansion = () => native.readInboxExpansion();
export const saveInboxExpansion = (projectId: string, expanded: boolean) =>
  native.saveInboxExpansion(projectId, expanded);
export const readInboxPinOrder = (userId: string, workspaceId: string) =>
  native.readInboxPinOrder(userId, workspaceId);
export const saveInboxPinOrder = (
  userId: string,
  workspaceId: string,
  ids: string[],
) => native.saveInboxPinOrder(userId, workspaceId, ids);
export const resetInboxPreferences = (userId: string, workspaceId: string) =>
  native.resetInboxPreferences(userId, workspaceId);

export const readLocalValue = (key: string) => native.readLocalValue(key);
export const searchInbox = (
  userId: string,
  workspaceId: string,
  query: string,
) => native.searchInbox(userId, workspaceId, query);
export const writeLocalValue = (
  key: string,
  value: string,
  generation?: number,
) =>
  generation === undefined
    ? native.writeLocalValue(key, value)
    : native.writeLocalValue(key, value, generation);
export const localStoreGeneration = () => native.localStoreGeneration();

export const debugBackgroundDataRuntime = (action: string) =>
  native.debugBackgroundDataRuntime(action);
