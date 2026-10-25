import { ShellPage } from '@/lib/presentation/ShellPage';
import { VerifyProviders } from '@/screens/debug/verifyProviders';
import { PageSafeArea } from './shellSafeArea';

export function ShellPageSurface({
  presentationId,
}: {
  presentationId: number;
}) {
  return (
    <PageSafeArea>
      <VerifyProviders owner={false}>
        <ShellPage presentationId={presentationId} />
      </VerifyProviders>
    </PageSafeArea>
  );
}
