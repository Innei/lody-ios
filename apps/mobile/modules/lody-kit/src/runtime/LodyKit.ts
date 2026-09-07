import { NativeModule, requireNativeModule } from 'expo';

export interface RuntimeInfo {
  offlineProbe?: boolean;
  moduleName: string;
  systemVersion: string;
}
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
  catalog?: string;
  revision?: number;
};
type Events = {
  onAppActive: () => void;
  onDataRuntime: (event: DataRuntimeEvent) => void;
};
declare class LodyKitNativeModule extends NativeModule<Events> {
  readLocalStartup(): Promise<{
    account?: string;
    workspace?: string;
    catalog?: string;
  }>;
  readLocalValue(key: string): Promise<string | null>;
  writeLocalValue(key: string, value: string): Promise<void>;
  clearLocalValues(): Promise<void>;
  readonly runtimeInfo: RuntimeInfo;
  readonly initialInboxView: number;
  saveInboxView(index: number): void;
  readInboxExpansion(): Record<string, boolean>;
  saveInboxExpansion(projectId: string, expanded: boolean): void;
  watchSession(id: string): Promise<void>;
  unwatchSession(id: string): Promise<void>;
  sessionCreationOptions(payload: string): Promise<string>;
  localProjects(payload: string): Promise<string>;
  createSession(payload: string): Promise<string>;
  archiveSession(payload: string): Promise<string>;
  pinSession(payload: string): Promise<string>;
  sendSessionTurn(payload: string): Promise<string>;
  sessionItemDetail(payload: string): Promise<string>;
  respondSessionPermission(payload: string): Promise<string>;
  turnDiff(payload: string): Promise<string>;
  fileDiff(payload: string): Promise<string>;
  readFile(payload: string): Promise<string>;
  listDir(payload: string): Promise<string>;
  readContentText(handle: string): Promise<string | null>;
  previewContent(handle: string): Promise<void>;
  watchCatalog(workspace: string, owner: string, userId: string): Promise<void>;
  unwatchCatalog(owner: string): Promise<void>;
  dataRuntimeStatus(): Promise<DataRuntimeEvent>;
  debugBackgroundDataRuntime(action: string): Promise<string>;
  debugHangDataRuntime(): Promise<void>;
  debugProbeSchema(): Promise<string>;
  debugRestartDataRuntime(): Promise<void>;
  selectionFeedback(): Promise<void>;
  showToast(message: string, kind: string): void;
  readAuthToken(): Promise<string | null>;
  saveAuthToken(token: string): Promise<void>;
  clearAuthToken(): Promise<void>;
  openAuthBrowser(url: string): Promise<void>;
  closeAuthBrowser(): Promise<void>;
  decodeFlock(
    snapshot: string,
    updates: string[],
    mode: string,
  ): Promise<string>;
}
const native = requireNativeModule<LodyKitNativeModule>('LodyKit');
export const runtimeInfo = native.runtimeInfo;
export function selectionFeedback(): Promise<void> {
  return native.selectionFeedback();
}

export type ToastKind = 'info' | 'warning' | 'error';

/** Rendered by a dedicated UIWindow above sheets, so it is never occluded. */
export function showToast(message: string, kind: ToastKind = 'error'): void {
  native.showToast(message, kind);
}
export function addAppActiveListener(listener: () => void) {
  return native.addListener('onAppActive', listener);
}

export const readAuthToken = () => native.readAuthToken();
export const saveAuthToken = (token: string) => native.saveAuthToken(token);
export const clearAuthToken = () => native.clearAuthToken();
export const openAuthBrowser = (url: string) => native.openAuthBrowser(url);
export const closeAuthBrowser = () => native.closeAuthBrowser();
export const decodeFlock = (
  snapshot: string,
  updates: string[],
  mode: string,
) => native.decodeFlock(snapshot, updates, mode);

export const watchCatalog = (
  workspace: string,
  owner: string,
  userId: string,
) => native.watchCatalog(workspace, owner, userId);
export const unwatchCatalog = (owner: string) => native.unwatchCatalog(owner);
export const addDataRuntimeListener = (
  listener: (event: DataRuntimeEvent) => void,
) => native.addListener('onDataRuntime', listener);
export const dataRuntimeStatus = () => native.dataRuntimeStatus();
export const debugHangDataRuntime = () => native.debugHangDataRuntime();
export const debugProbeSchema = () => native.debugProbeSchema();
export const debugRestartDataRuntime = () => native.debugRestartDataRuntime();

export const watchSession = (id: string) => native.watchSession(id);
export const unwatchSession = (id: string) => native.unwatchSession(id);
export const sendSessionTurn = (payload: string) =>
  native.sendSessionTurn(payload);
export const sessionItemDetail = (payload: string) =>
  native.sessionItemDetail(payload);
export const respondSessionPermission = (payload: string) =>
  native.respondSessionPermission(payload);
export const turnDiffRaw = (payload: string) => native.turnDiff(payload);
export const fileDiffRaw = (payload: string) => native.fileDiff(payload);
export const readFileRaw = (payload: string) => native.readFile(payload);
export const listDirRaw = (payload: string) => native.listDir(payload);
export const readContentText = (handle: string) =>
  native.readContentText(handle);
export const previewContent = (handle: string) => native.previewContent(handle);

export const sessionCreationOptions = (payload: string) =>
  native.sessionCreationOptions(payload);
export const createSession = (payload: string) => native.createSession(payload);
export const archiveSession = (payload: string) =>
  native.archiveSession(payload);
export const pinSession = (payload: string) => native.pinSession(payload);

export const initialInboxView = native.initialInboxView === 1 ? 1 : 0;
export const saveInboxView = (index: number) => native.saveInboxView(index);
export const readInboxExpansion = () => native.readInboxExpansion();
export const saveInboxExpansion = (projectId: string, expanded: boolean) =>
  native.saveInboxExpansion(projectId, expanded);

export const readLocalValue = (key: string) => native.readLocalValue(key);
export const writeLocalValue = (key: string, value: string) =>
  native.writeLocalValue(key, value);
export const clearLocalValues = () => native.clearLocalValues();

export const readLocalStartup = () => native.readLocalStartup();

export const localProjects = (payload: string) => native.localProjects(payload);

export const debugBackgroundDataRuntime = (action: string) =>
  native.debugBackgroundDataRuntime(action);
