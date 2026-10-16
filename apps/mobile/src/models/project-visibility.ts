import { z } from 'zod';
export const visibilitySchema = z.object({
  userId: z.string().min(1),
  rows: z
    .array(
      z.object({
        machineId: z.string().min(1),
        localProjectId: z.string().min(1),
        ownerUserId: z.string().min(1),
        sharedWithTeam: z.boolean(),
        updatedAt: z.number().finite().nonnegative(),
      }),
    )
    .max(10000),
});
export type VisibilitySnapshot = z.infer<typeof visibilitySchema>;
export type VisibilityRow = VisibilitySnapshot['rows'][number];
export type VisibilityRequest = { page: 'projects'; workspaceId: string } & (
  | { action: 'list' }
  | {
      action: 'set';
      machineId: string;
      localProjectId: string;
      sharedWithTeam: boolean;
    }
);
export type VisibilityService = (
  request: VisibilityRequest,
) => Promise<VisibilitySnapshot>;
