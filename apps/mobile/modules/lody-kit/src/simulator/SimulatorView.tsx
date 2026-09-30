import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { ViewProps } from 'react-native';

export const SimulatorView: ComponentType<
  ViewProps & { sourceJSON: string; commandJSON: string }
> = requireNativeView('LodyKit', 'LodySimulatorView');
