import { ScrollView, View } from 'react-native';
import { AppText } from '@/ui/AppText';
import type { DetailBlock } from '@lody/cloud-runtime/models/session';

function Mono({ children, color }: { children: string; color?: unknown }) {
  return (
    <AppText
      variant="mono"
      selectable
      style={color ? { color: color as string } : undefined}
    >
      {children}
    </AppText>
  );
}

export function CommandBlock({ block }: { block: DetailBlock }) {
  return (
    <View style={{ gap: 2 }}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false}>
        <Mono>{`$ ${[block.command, ...(block.args ?? [])].join(' ')}`}</Mono>
      </ScrollView>
      {block.cwd ? <AppText variant="meta">{block.cwd}</AppText> : null}
    </View>
  );
}
