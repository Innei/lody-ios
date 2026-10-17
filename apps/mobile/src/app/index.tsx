import { homeVerify } from '@/screens/debug/HomePreviewScreen';
import { uiVerify } from '@/screens/debug/uiVerify';
import { HomeScreen } from '@/screens/HomeScreen';
import { Redirect } from 'expo-router';
function DebugRedirect() {
  return <Redirect href="/debug" />;
}

let Entry = HomeScreen.Route;
if (uiVerify && !homeVerify) Entry = DebugRedirect;

export default Entry;
