export const catalogKey = (userId: string, workspaceId: string) =>
  `catalog:${userId}:${workspaceId}`;
export const selectionKey = (userId: string) => `workspace:${userId}`;
