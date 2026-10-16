import { requireNativeModule } from 'expo';
const native = requireNativeModule<{
  workspaceSettings(payload: string): Promise<string>;
}>('LodyKit');
export const workspaceSettingsRaw = (payload: string) =>
  native.workspaceSettings(payload);
