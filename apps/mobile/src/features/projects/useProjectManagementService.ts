import { useEffect, useMemo, useState } from 'react';
import { uuid } from '@lody-ios/kit';
import {
  cancelProjectManagement,
  requestProjectManagement,
  type ProjectManagementService,
} from '@/cloud/project-management';

export function useProjectManagementService(
  workspaceId: string,
  supplied?: ProjectManagementService,
) {
  const [editorId] = useState(() => uuid.v4());
  const service = useMemo<ProjectManagementService>(
    () =>
      supplied ??
      ((request) => requestProjectManagement(workspaceId, editorId, request)),
    [supplied, workspaceId, editorId],
  );
  useEffect(
    () => () => {
      if (!supplied) cancelProjectManagement(workspaceId, editorId);
    },
    [supplied, workspaceId, editorId],
  );
  return service;
}
