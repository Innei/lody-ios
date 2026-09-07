export type ListStateInput = {
  loading?: boolean;
  filtered?: boolean;
  connected?: boolean;
};

/** One placeholder for loading, empty search, offline and first run. */
export function listPlaceholder({
  loading = false,
  filtered = false,
  connected = true,
}: ListStateInput) {
  if (loading) return '正在载入你的会话…';
  if (filtered) return '没有匹配的会话';
  if (!connected) return '连接已中断，下拉重试。';
  return '会话会在连接电脑后出现在这里';
}

export function searchPlaceholder({
  signedIn,
  query,
  loading,
  connected,
}: {
  signedIn: boolean;
  query: string;
  loading: boolean;
  connected: boolean;
}) {
  if (!signedIn) return '登录后搜索你的项目和会话';
  if (!query.trim()) return '搜索当前工作区的项目和会话，包括已归档会话';
  if (loading) return '正在载入…';
  if (!connected) return '连接已中断，请在会话页重新同步';
  return '没有匹配的项目或会话';
}
