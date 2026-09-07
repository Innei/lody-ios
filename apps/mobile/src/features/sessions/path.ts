export const basename = (path: string) =>
  path.split(/[\\/]/).filter(Boolean).at(-1) || path;
export const dirname = (path: string) =>
  path.split(/[\\/]/).filter(Boolean).slice(0, -1).join('/');
