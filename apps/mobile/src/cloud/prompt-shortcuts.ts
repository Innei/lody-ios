import { promptShortcutsRaw } from '@lody-ios/kit';
import type {
  ShortcutRequest,
  PromptShortcut,
  PromptShortcutIndexEntry,
} from '@lody/cloud-runtime/models/prompt-shortcuts';
export type ShortcutService = (
  request: ShortcutRequest,
) => Promise<
  PromptShortcutIndexEntry[] | PromptShortcut | PromptShortcutIndexEntry
>;
export const requestShortcuts: ShortcutService = async (request) =>
  JSON.parse(await promptShortcutsRaw(JSON.stringify(request)));
