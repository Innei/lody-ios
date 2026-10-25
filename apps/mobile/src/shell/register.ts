import { registerRootComponent } from 'expo';
import { AppRegistry } from 'react-native';
import { installShellNavigation } from '@/lib/presentation/shellNavigation';

import { ShellPageSurface } from './ShellPageSurface';
import { ShellRoot } from './ShellRoot';
import './shellPages';

installShellNavigation();
registerRootComponent(ShellRoot);
AppRegistry.registerComponent('LodyPage', () => ShellPageSurface);
