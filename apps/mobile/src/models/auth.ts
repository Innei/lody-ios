export type User = { id: string; name: string; email: string };
export type Workspace = { id: string; name: string; slug: string | null };
export type DeviceCode = {
  device_code: string;
  user_code: string;
  verification_uri_complete: string;
  expires_in: number;
  interval: number;
};
export type SavedAccount = { user: User; workspaces: Workspace[] };
