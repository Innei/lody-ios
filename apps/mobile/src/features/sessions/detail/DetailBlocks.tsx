import { useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { NativeDiff } from '@lody-ios/kit';
import { usePalette } from '@/theme/palette';
import { AppText } from '@/ui/AppText';
import { t } from '../../../i18n/index.ts';

export type DetailBlock = {
  type: string;
  path?: string;
  oldText?: string;
  newText?: string;
  command?: string;
  args?: string[];
  cwd?: string;
  output?: string;
  exitStatus?: { exitCode?: number | null; signal?: string | null };
};

export type DetailResponse = {
  itemId: string;
  rev: number;
  blocks: DetailBlock[];
  rawInput?: unknown;
  rawOutput?: unknown;
  options?: { optionId: string; name: string; kind: string }[];
  outcome?: unknown;
  truncated: boolean;
  nextCursor?: string;
};

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
      <NativeDiff
        path={block.path ?? ''}
        oldText={block.oldText ?? ''}
        newText={block.newText ?? ''}
        scrollEnabled={false}
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
