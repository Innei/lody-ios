import { homeVerify } from '@/screens/debug/HomePreviewScreen';
import { uiVerify } from '@/screens/debug/uiVerify';
import { InboxScreen } from '@/screens/InboxScreen';
import { PadHomeScreen } from '@/screens/PadHomeScreen';
import { Redirect } from 'expo-router';
import { Platform } from 'react-native';
function DebugRedirect() {
  return <Redirect href="/debug" />;
}

let Entry = InboxScreen.Route;
if (Platform.OS === 'ios' && Platform.isPad) Entry = PadHomeScreen.Route;
if (uiVerify && !homeVerify) Entry = DebugRedirect;

export default Entry;
