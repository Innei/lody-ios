import { mentionCatalogRaw } from '../runtime/LodyKit';
import type {
  MentionCatalog,
  MentionCategory,
  MentionSource,
} from '../../../../src/models/mentions';

export async function getMentionCatalog(
  source: MentionSource,
  category: MentionCategory,
): Promise<MentionCatalog> {
  return JSON.parse(
    await mentionCatalogRaw(JSON.stringify({ ...source, category })),
  );
}
