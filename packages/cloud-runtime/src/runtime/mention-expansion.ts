import type {
  MentionCatalog,
  MentionCategory,
  MentionItem,
} from '../models/mentions';
import {
  parsePromptShortcut,
  shortcutAvailability,
  shortcutFailure,
  shortcutScopeIssue,
  type PromptShortcut,
  type PromptShortcutScope,
  type PromptShortcutTarget,
} from '../models/prompt-shortcuts.ts';

// Explicit session/Role IDs survive native text-only draft restoration and
// renames. Quoted file references own their text, including any dollar signs.
const referencePattern =
  /@"(?:\\.|[^"\\])*"|(^|\s)(\$[^\s$@]+|@(?:session|role|shortcut):[^\s@]+)(?=\s|$)/g;

function categoryOf(token: string): MentionCategory {
  if (token.startsWith('$')) return 'skill';
  if (token.startsWith('@session:')) return 'session';
  if (token.startsWith('@shortcut:')) return 'shortcut';
  return 'role';
}

export async function expandMentions(
  text: string,
  load: (category: MentionCategory) => Promise<MentionCatalog>,
  shortcut?: (id: string) => Promise<string>,
): Promise<string> {
  const categories = new Set<MentionCategory>();
  const tokens = new Set<string>();
  for (const match of text.matchAll(referencePattern)) {
    if (!match[2]) continue;
    if (categoryOf(match[2]) === 'shortcut') tokens.add(match[2]);
    else categories.add(categoryOf(match[2]));
  }
  try {
    const shortcuts = new Map<string, string>();
    for (const token of tokens) {
      if (!shortcut) throw new Error('shortcut_not_found');
      shortcuts.set(
        token,
        await shortcut(decodeURIComponent(token.slice('@shortcut:'.length))),
      );
    }
    const catalogs = await Promise.all([...categories].map(load));
    // A partial skill scan can hide the project override of a global token.
    if (catalogs.some((catalog) => catalog.incomplete || catalog.truncated))
      throw new Error('mention_catalog_incomplete');
    return expandMentionText(
      text,
      catalogs.flatMap((catalog) => catalog.items),
      shortcuts,
    );
  } catch (error) {
    if (error instanceof Error && error.message.startsWith('shortcut_'))
      throw error;
    throw new Error('mention_expansion_failed');
  }
}

export function expandMentionText(
  text: string,
  items: readonly MentionItem[],
  shortcuts = new Map<string, string>(),
): string {
  const byToken = new Map<string, MentionItem>();
  const ambiguous = new Set<string>();
  for (const item of items) {
    if (!item.insertText) continue;
    if (byToken.has(item.insertText)) ambiguous.add(item.insertText);
    byToken.set(item.insertText, item);
  }
  // One pass over the original text: expansion text is never re-interpreted.
  return text.replace(
    referencePattern,
    (whole, space: string, token: string, offset: number) => {
      if (!token) return whole;
      if (token.startsWith('@shortcut:')) {
        if (!shortcuts.has(token)) throw new Error('shortcut_not_found');
        return space + shortcuts.get(token)!;
      }
      const item = byToken.get(token);
      if (!item) return whole;
      if (ambiguous.has(token)) throw new Error('ambiguous_mention');
      if (
        item.kind === 'skill' &&
        /^\s*\[Skill Path\]\(/.test(text.slice(offset + whole.length))
      )
        return whole;
      return space + mentionPrompt(item);
    },
  );
}

export function mentionPrompt(item: MentionItem): string {
  if (item.kind === 'session')
    return `use lody mcp to query session[id: ${item.path}] history`;
  if (item.kind === 'role')
    return `use lody mcp to create a session with agent role[id: ${item.path}, name: ${item.name}]`;
  if (item.kind === 'skill') {
    const destination = item.path.replace(/\\/g, '\\\\').replace(/\)/g, '\\)');
    const token =
      item.insertText?.slice(1) ?? item.name.trim().replace(/\s+/g, '-');
    return `use /${token} [Skill Path](${destination})`;
  }
  return item.insertText ?? `@${item.path}`;
}

const targetCategories = {
  file: 'file',
  skill: 'skill',
  agent_role: 'role',
  issue: 'issue',
  pull_request: 'pr',
} as const;
export async function resolveShortcutTargets(
  scope: PromptShortcutScope,
  targets: readonly PromptShortcutTarget[],
  load: (category: MentionCategory) => Promise<MentionCatalog>,
  check: () => void = () => {},
) {
  const result = new Map<PromptShortcutTarget, MentionItem>();
  const catalogs = new Map<MentionCategory, MentionCatalog>();
  for (const target of targets) {
    const issue = shortcutScopeIssue(scope, target);
    if (issue) shortcutFailure(issue);
    const category = targetCategories[target.kind];
    let catalog = catalogs.get(category);
    if (!catalog) {
      catalog = await load(category);
      check();
      if (catalog.incomplete || catalog.truncated)
        shortcutFailure('dependencies_unverified');
      catalogs.set(category, catalog);
    }
    const item = catalog.items.find((item) => {
      if (item.disabledReason) return false;
      if (target.kind === 'file')
        return (
          item.path === target.path &&
          item.kind === (target.directory ? 'directory' : 'file')
        );
      if (target.kind === 'skill')
        return (
          item.kind === 'skill' &&
          item.path === target.path &&
          item.scope === target.source
        );
      if (target.kind === 'agent_role')
        return item.kind === 'role' && item.path === target.agentRoleId;
      return (
        item.kind === targetCategories[target.kind] &&
        item.path === `${targetCategories[target.kind]}:${target.number}`
      );
    });
    if (!item) shortcutFailure('dependency_missing');
    result.set(target, item);
  }
  return result;
}
export async function expandShortcutTemplate(
  value: PromptShortcut,
  context: { workspaceId: string; userId: string; scope: PromptShortcutScope },
  load: (category: MentionCategory) => Promise<MentionCatalog>,
  check: () => void = () => {},
): Promise<string> {
  value = parsePromptShortcut(value);
  const availability = shortcutAvailability(value, context);
  if (availability !== 'available') shortcutFailure(availability);
  const targets = await resolveShortcutTargets(
    value.scope,
    value.mentions.map((mention) => mention.target),
    load,
    check,
  );
  let result = '',
    offset = 0;
  for (const mention of value.mentions) {
    result +=
      value.prompt.slice(offset, mention.start) +
      mentionPrompt(targets.get(mention.target)!);
    offset = mention.end;
  }
  check();
  return result + value.prompt.slice(offset);
}
