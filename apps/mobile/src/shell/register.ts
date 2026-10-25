import { registerRootComponent } from 'expo';
import { AppRegistry } from 'react-native';
import { ShellPage } from '@/lib/presentation/ShellPage';
import { installShellNavigation } from '@/lib/presentation/shellNavigation';

import { ShellRoot } from './ShellRoot';

installShellNavigation();
registerRootComponent(ShellRoot);
AppRegistry.registerComponent('LodyPage', () => ShellPage);
