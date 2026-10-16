import { workspaceSettingsRaw } from '@lody-ios/kit';
import {
  visibilitySchema,
  type VisibilityService,
} from '@/models/project-visibility';
export const requestVisibility: VisibilityService = async (request) =>
  visibilitySchema.parse(
    JSON.parse(await workspaceSettingsRaw(JSON.stringify(request))),
  );
