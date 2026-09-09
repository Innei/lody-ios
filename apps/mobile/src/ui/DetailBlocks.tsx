import { useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { NativeInlineDiff } from '@lody-ios/kit';
import { usePalette } from '@/lib/theme/palette';
import { AppText } from '@/ui/AppText';
import { t } from '../lib/i18n/index.ts';
import type { DetailBlock } from '../models/session.ts';

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

export function DiffBlock({ block }: { block: DetailBlock }) {
  const [height, setHeight] = useState(0);
  const [failed, setFailed] = useState(false);
  if (failed) return <Mono>{JSON.stringify(block, null, 2)}</Mono>;
  return (
    <View style={{ gap: 6 }}>
      {block.path ? <AppText variant="meta">{block.path}</AppText> : null}
      <NativeInlineDiff
        path={block.path ?? ''}
        oldText={block.oldText ?? ''}
        newText={block.newText ?? ''}
        style={{
          height: Math.max(height, 44),
          borderRadius: 12,
          overflow: 'hidden',
        }}
        onRender={({ nativeEvent }) => setHeight(nativeEvent.contentHeight)}
        onFail={() => setFailed(true)}
      />
    </View>
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

export function OutputBlock({ block }: { block: DetailBlock }) {
  const colors = usePalette();
  const code = block.exitStatus?.exitCode;
  return (
    <View
      style={{
        backgroundColor: colors.fill,
        borderRadius: 12,
        borderCurve: 'continuous',
        padding: 12,
        gap: 6,
      }}
    >
      {typeof code === 'number' && code !== 0 ? (
        <AppText variant="meta" style={{ color: colors.danger }}>
          {t('detail.exitCode', { code })}
        </AppText>
      ) : null}
      <ScrollView horizontal showsHorizontalScrollIndicator={false}>
        <Mono>{block.output ?? ''}</Mono>
      </ScrollView>
    </View>
  );
}

export function RawBlock({ title, value }: { title: string; value: unknown }) {
  const [expanded, setExpanded] = useState(false);
  const colors = usePalette();
  if (value === undefined) return null;
  return (
    <View style={{ gap: 6 }}>
      <Pressable
        accessibilityRole="button"
        accessibilityState={{ expanded }}
        onPress={() => setExpanded((v) => !v)}
        style={{ minHeight: 44, justifyContent: 'center' }}
      >
        <AppText variant="meta" style={{ color: colors.accent }}>
          {t(expanded ? 'detail.collapse' : 'detail.expand', { title })}
        </AppText>
      </Pressable>
      {expanded ? (
        <ScrollView horizontal showsHorizontalScrollIndicator={false}>
          <Mono>{JSON.stringify(value, null, 2)}</Mono>
        </ScrollView>
      ) : null}
    </View>
  );
}

export function Blocks({ blocks }: { blocks: DetailBlock[] }) {
  return (
    <>
      {blocks.map((block, index) =>
        block.type === 'diff' ? (
          <DiffBlock key={index} block={block} />
        ) : block.type === 'terminal_command' ? (
          <CommandBlock key={index} block={block} />
        ) : block.type === 'terminal_output' ? (
          <OutputBlock key={index} block={block} />
        ) : (
          <Mono key={index}>{JSON.stringify(block, null, 2)}</Mono>
        ),
      )}
    </>
  );
}
