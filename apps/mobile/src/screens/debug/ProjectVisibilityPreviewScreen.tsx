import { useMemo } from 'react';
import { definePage } from '@/lib/presentation';
import type {
  VisibilityService,
  VisibilitySnapshot,
} from '@/features/settings/project-visibility';
import { ProjectVisibilityView } from '../ProjectVisibilityScreen';
const catalog = {
  projects: [
    {
      id: 'm1:local:same',
      machineId: 'm1',
      name: 'Studio',
      rootPath: '/Users/owner/Studio',
    },
    {
      id: 'm2:local:same',
      machineId: 'm2',
      name: 'Studio',
      rootPath: '/Users/teammate/Studio',
    },
    {
      id: 'm1:local:unregistered',
      machineId: 'm1',
      name: 'Draft',
      rootPath: '/Users/owner/Draft',
    },
  ],
  sessions: [],
  machineIds: ['m1', 'm2'],
  machineNames: { m1: 'Studio Mac', m2: 'Studio Mac' },
};
function Preview() {
  const service = useMemo<VisibilityService>(() => {
    let fail = true;
    const snapshot: VisibilitySnapshot = {
      userId: 'owner',
      rows: [
        {
          machineId: 'm1',
          localProjectId: 'same',
          ownerUserId: 'owner',
          sharedWithTeam: false,
          updatedAt: 1,
        },
        {
          machineId: 'm2',
          localProjectId: 'same',
          ownerUserId: 'teammate',
          sharedWithTeam: true,
          updatedAt: 1,
        },
      ],
    };
    return async (request) => {
      if (request.action === 'set') {
        if (fail) {
          fail = false;
          throw new Error('unknown');
        }
        snapshot.rows[0].sharedWithTeam = request.sharedWithTeam;
      }
      return JSON.parse(JSON.stringify(snapshot)) as VisibilitySnapshot;
    };
  }, []);
  return (
    <ProjectVisibilityView
      workspaceId="visibility-fixture"
      catalog={catalog}
      service={service}
    />
  );
}
export const ProjectVisibilityPreviewScreen = definePage({
  id: 'project-visibility-preview',
  title: 'Projects',
  Component: Preview,
  presentation: { headerVariant: 'transparent' },
});
