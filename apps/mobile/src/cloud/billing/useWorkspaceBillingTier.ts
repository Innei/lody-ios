import { useEffect, useState } from 'react';
import { workspaceBillingEntitlement } from '@lody-ios/kit';

type Tier = 'free' | 'plus' | 'enterprise';

export function useWorkspaceBillingTier(
  workspaceId: string,
  userId: string,
  watch: boolean,
): Tier | undefined {
  const key = `${userId}:${workspaceId}`;
  const [current, setCurrent] = useState<{ key: string; tier?: Tier }>();
  useEffect(() => {
    if (!watch || !workspaceId || !userId) return;
    let active = true;
    const refresh = async () => {
      try {
        const raw = await workspaceBillingEntitlement(workspaceId, userId);
        const value: unknown = JSON.parse(raw);
        const tier =
          value && typeof value === 'object' && 'effectivePlanTier' in value
            ? value.effectivePlanTier
            : undefined;
        if (!active) return;
        setCurrent({
          key,
          tier:
            tier === 'free' || tier === 'plus' || tier === 'enterprise'
              ? tier
              : undefined,
        });
      } catch {
        if (active) setCurrent({ key });
      }
    };
    void refresh();
    const timer = setInterval(() => void refresh(), 60_000);
    return () => {
      active = false;
      clearInterval(timer);
    };
  }, [key, userId, workspaceId, watch]);
  return watch && current?.key === key ? current.tier : undefined;
}
