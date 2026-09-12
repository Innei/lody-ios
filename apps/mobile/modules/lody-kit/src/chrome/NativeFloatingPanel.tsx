import { requireNativeView } from 'expo';
import type { ComponentType, ReactNode } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type NativeEmbeddedSheetProps = ViewProps & {
  children: ReactNode;
  dismissRequest: number;
  grabberAccessibility: {
    label: string;
    medium: string;
    large: string;
  };
  grabberAccessibilityIdentifier?: string;
  mediumFraction?: number;
  onDismiss: () => void;
};

const EmbeddedSheetView = requireNativeView(
  'LodyKit',
  'LodyEmbeddedSheet',
) as ComponentType<
  Omit<NativeEmbeddedSheetProps, 'onDismiss'> & {
    onDismiss: (event: NativeSyntheticEvent<Record<string, never>>) => void;
  }
>;

export function NativeEmbeddedSheet({
  mediumFraction = 0.62,
  onDismiss,
  ...props
}: NativeEmbeddedSheetProps) {
  return (
    <EmbeddedSheetView
      {...props}
      mediumFraction={mediumFraction}
      onDismiss={onDismiss}
    />
  );
}
