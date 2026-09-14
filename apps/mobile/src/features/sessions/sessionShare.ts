const SHARE_ORIGIN = 'https://lody.ai';

export function sessionShareUrl(
  workspace: { id: string; slug: string | null },
  sessionId: string,
) {
  const slug = workspace.slug?.trim() || workspace.id;
  if (!slug || !sessionId) return;
  if (/[/\\?#]/.test(slug) || /[/\\?#]/.test(sessionId)) return;
  return `${SHARE_ORIGIN}/${slug}/sessions/${sessionId}`;
}
