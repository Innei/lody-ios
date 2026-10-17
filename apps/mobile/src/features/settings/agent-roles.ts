import type { NativeListSection } from '@lody-ios/kit';
import type { AgentRoleItem } from '@lody/cloud-runtime/models/agent-roles';
import { t } from '@/lib/i18n';
export const roleEditable = (role: AgentRoleItem, userId: string) =>
  role.ownerUserId === userId &&
  Array.from(role.name).length <= 60 &&
  Array.from(role.description).length <= 140 &&
  role.promptPrefix.length <= 32000;
export function roleReadOnlyHint(role: AgentRoleItem, userId: string) {
  if (role.ownerUserId !== userId) return t('settings.roles.readOnly');
  if (!roleEditable(role, userId)) return t('settings.roles.longReadOnly');
  return undefined;
}
export function roleSections(
  roles: AgentRoleItem[],
  userId: string,
): NativeListSection[] {
  const labels = {
    private: t('settings.roles.private'),
    workspace: t('settings.roles.sharedValue'),
  };
  return [
    {
      id: 'roles',
      footer: t('settings.roles.hint'),
      rows: roles.map((role) => ({
        id: `role:${role.id}`,
        title: role.name,
        image: 'person.crop.square',
        subtitle: [
          role.description,
          ...role.targets.map(
            (target) =>
              `${target.machineName} · ${target.agentName}${target.state === 'configured' ? '' : ` · ${t(`settings.roles.${target.state}`)}`}`,
          ),
          role.ownerUserId !== userId ? t('settings.roles.ownerOnly') : '',
        ]
          .filter(Boolean)
          .join('\n'),
        wrapSubtitle: true,
        value: labels[role.visibility],
        accessibilityValue: labels[role.visibility],
        action: true,
        disclosure: true,
      })),
    },
  ];
}
