import { z } from 'zod';
const authorization = z.discriminatedUnion('state', [
  z.object({ state: z.literal('missing') }),
  z.object({
    state: z.literal('expired'),
    githubAccountId: z.string().optional(),
  }),
  z.object({
    state: z.literal('authorized'),
    githubAccountId: z.string().min(1),
    profile: z.object({ login: z.string().min(1) }).optional(),
  }),
]);
export const githubSettingsSchema = z.object({
  canManage: z.boolean(),
  roleKnown: z.boolean(),
  repositories: z
    .array(
      z.object({
        repoFullName: z.string().regex(/^[^/\s]+\/[^/\s]+$/),
        name: z.string(),
        repositoryId: z.number().int().positive(),
        private: z.boolean(),
        enabled: z.boolean(),
      }),
    )
    .max(10000)
    .nullable(),
  personal: z.object({ enabled: z.boolean(), authorization }).nullable(),
  errors: z.array(z.enum(['repositories', 'personal'])),
});
export type GitHubSettings = z.infer<typeof githubSettingsSchema>;
export type GitHubSettingsRequest = { page: 'github'; workspaceId: string } & (
  | { action: 'list' }
  | { action: 'repository'; repoFullName: string; enabled: boolean }
  | { action: 'preference'; enabled: boolean }
  | { action: 'install' }
);
export type GitHubSettingsService = (
  request: GitHubSettingsRequest,
) => Promise<GitHubSettings | { url: string }>;
