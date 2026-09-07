import { homeVerify } from '@/screens/debug/HomePreviewScreen';
import { uiVerify } from '@/screens/debug/uiVerify';
import { Redirect } from 'expo-router';
export default function Index() {
  return (
    <Redirect href={uiVerify && !homeVerify ? '/debug' : '/(tabs)/sessions'} />
  );
}
