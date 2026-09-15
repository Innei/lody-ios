import type { SharedObject } from 'expo';
import { native } from '../runtime/LodyKit';

/** Decoded native history owned by this navigation, released with its JS owner. */
export declare class PreparedChatEntries extends SharedObject {}

export const prepareChatEntries = (
  json: string,
): Promise<PreparedChatEntries> => native.prepareChatEntries(json);
