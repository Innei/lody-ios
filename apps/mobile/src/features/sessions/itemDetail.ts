import { sessionItemDetail } from '@lody-ios/kit';
import type { DetailResponse } from '../../models/session.ts';

export async function fetchDetail(params: {
  sessionId: string;
  entryId: string;
  itemId: string;
  cursor?: string;
}): Promise<DetailResponse> {
  return JSON.parse(await sessionItemDetail(JSON.stringify(params)));
}
