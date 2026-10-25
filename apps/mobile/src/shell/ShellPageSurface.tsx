import { ThemeProvider } from 'expo-router';
import { ShellPage } from '@/lib/presentation/ShellPage';
import { useNavigationTheme } from '@/lib/theme/navigationTheme';
import { VerifyProviders } from '@/screens/debug/verifyProviders';
import { PageSafeArea } from './shellSafeArea';

export function ShellPageSurface({
  presentationId,
}: {
  presentationId: number;
}) {
  const theme = useNavigationTheme();
  return (
    <PageSafeArea>
      <ThemeProvider value={theme}>
        <VerifyProviders owner={false}>
          <ShellPage presentationId={presentationId} />
        </VerifyProviders>
      </ThemeProvider>
    </PageSafeArea>
  );
}
