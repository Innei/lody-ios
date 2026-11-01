import { LoroMap, type LoroDoc } from 'loro-crdt/base64';
import type { SessionQueueRequest } from '../contract/queue.ts';

// An opaque conflict fingerprint, never the configuration or its private fields.
function revision(value: unknown) {
  let hash = 14695981039346656037n;
  for (const char of JSON.stringify(value)) {
    hash ^= BigInt(char.codePointAt(0)!);
    hash = BigInt.asUintN(64, hash * 1099511628211n);
  }
  return hash.toString(16);
}

export function readSessionQueue(doc: LoroDoc) {
  const queue = doc.getMovableList('mq');
  return Array.from({ length: queue.length }, (_, index) => {
    const item = queue.get(index);
    if (!(item instanceof LoroMap)) throw new Error('invalid_queue');
    const raw = item.toJSON() as Record<string, any>;
    const blocks = raw.acpSessionConfig?.inputBlocks;
    const text = Array.isArray(blocks)
      ? blocks
          .filter((block) => block.type === 'text')
          .map((block) => block.text ?? '')
          .join('\n')
      : (raw.acpSessionConfig?.prompt ?? raw.task ?? '');
    return {
      id: item.id,
      revision: revision(raw),
      ...(typeof raw.userTurnId === 'string'
        ? { messageId: raw.userTurnId }
        : {}),
      text: String(text),
      attachments: Array.isArray(blocks)
        ? blocks
            .filter((block) => ['image', 'file'].includes(block.type))
            .map((block) => String(block.fileName ?? block.type))
        : [],
      editing: raw.isEditing === true,
      ...(typeof raw._lodyEditorId === 'string'
        ? { editToken: raw._lodyEditorId }
        : {}),
    };
  });
}

export function mutateSessionQueue(
  doc: LoroDoc,
  args: Exclude<SessionQueueRequest, { action: 'list' }>,
) {
  const queue = doc.getMovableList('mq');
  const items = readSessionQueue(doc);
  const index = items.findIndex((item) => item.id === args.id);
  const current = items[index];
  if (!current || current.revision !== args.revision) return false;
  const item = queue.get(index);
  if (!(item instanceof LoroMap)) return false;
  if (args.action === 'save' || args.action === 'cancel') {
    if (!current.editing || current.editToken !== args.editToken) return false;
  } else if (current.editing) return false;

  switch (args.action) {
    case 'begin':
      item.set('isEditing', true);
      item.set('editingStartedAt', Date.now());
      item.set('_lodyEditorId', args.editToken);
      break;
    case 'save': {
      const config = item.get('acpSessionConfig');
      if (!(config instanceof LoroMap)) throw new Error('invalid_queue');
      const raw = config.toJSON() as Record<string, any>;
      const retained = Array.isArray(raw.inputBlocks)
        ? raw.inputBlocks.filter((block) => block.type !== 'text')
        : [];
      const text = args.text.trim();
      if (!text && !retained.length) throw new Error('empty_message');
      config.set('prompt', text);
      config.set('inputBlocks', [
        ...(text ? [{ type: 'text', text }] : []),
        ...retained,
      ]);
      item.set('task', text);
      item.set('isEditing', false);
      item.delete('editingStartedAt');
      item.delete('_lodyEditorId');
      break;
    }
    case 'cancel':
      item.set('isEditing', false);
      item.delete('editingStartedAt');
      item.delete('_lodyEditorId');
      break;
    case 'remove':
      queue.delete(index, 1);
      break;
    case 'move': {
      const destination = items.findIndex(
        (candidate) => candidate.id === args.overId,
      );
      if (destination < 0 || items[destination].editing) return false;
      queue.move(index, destination);
      break;
    }
  }
  doc.commit();
  return true;
}
