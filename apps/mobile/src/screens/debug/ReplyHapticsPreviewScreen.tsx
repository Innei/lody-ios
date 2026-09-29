import { useCallback, useRef, useState } from 'react';
import { ActionSheetIOS, AppState } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { NativeGroupedList, debugReplyHaptics } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';

const defaults = {
  window: 5000,
  duration: 1800,
  interval: 70,
  count: 17,
  intensity: 0.6,
  endIntensity: 0.1,
  curve: 0.6,
  sharpness: 0.35,
  firstDelay: 1400,
  gap: 90,
  burst: 0.8,
  chunkChars: 6,
  seed: 7,
};
type Config = typeof defaults;
const hapticControls = [
  {
    key: 'window',
    title: '发送后触发窗口（ms）',
    values: [1000, 3000, 5000, 10000],
  },
  {
    key: 'duration',
    title: '首字后持续（ms）',
    values: [600, 1200, 1800, 3000],
  },
  { key: 'interval', title: '最短间隔（ms）', values: [40, 70, 100, 150] },
  { key: 'count', title: '最多次数', values: [3, 8, 17, 30] },
  { key: 'intensity', title: '起始强度', values: [0.3, 0.4, 0.6, 0.8, 1] },
  { key: 'endIntensity', title: '结束强度', values: [0.05, 0.1, 0.2, 0.4] },
  {
    key: 'curve',
    title: '衰减曲线（1 为线性）',
    values: [0.4, 0.6, 1, 1.6, 2.5],
  },
  { key: 'sharpness', title: '锐度', values: [0.1, 0.35, 0.6, 0.9] },
] as const;
const networkControls = [
  { key: 'firstDelay', title: '首字延迟（ms）', values: [0, 900, 1400, 6000] },
  { key: 'gap', title: 'chunk 平均间隔（ms）', values: [30, 45, 90, 160] },
  { key: 'burst', title: '突发度', values: [0, 0.3, 0.8] },
  { key: 'chunkChars', title: '每个 chunk 字数', values: [2, 4, 6, 20] },
] as const;
const controls = [...hapticControls, ...networkControls];
const reply =
  '收到，我正在为你整理这个想法。文字逐渐出现时，感受一下指尖轻轻的反馈。';

function random(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function planChunks(config: Config) {
  const next = random(config.seed);
  const chunks: { at: number; length: number }[] = [];
  let at = config.firstDelay * (0.9 + next() * 0.2);
  let length = 0;
  while (length < reply.length) {
    const size = Math.max(
      1,
      Math.round(config.chunkChars * (0.4 + next() * 1.2)),
    );
    length = Math.min(reply.length, length + size);
    chunks.push({ at, length });
    const stall = next() < 0.25 * config.burst;
    at += stall
      ? config.gap * (1 + config.burst * 6) * (0.7 + next() * 0.6)
      : config.gap * (1 - config.burst * 0.85) * (0.6 + next() * 0.8);
  }
  return chunks;
}

function View() {
  const colors = usePalette();
  const [config, setConfig] = useState(defaults);
  const [text, setText] = useState('点击模拟发送，感受回复开始出现时的触感。');
  const [status, setStatus] = useState('就绪');
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);
  const generation = useRef(0);
  const stop = useCallback(() => {
    generation.current++;
    timers.current.forEach(clearTimeout);
    timers.current = [];
    void debugReplyHaptics([], defaults).catch(() => {});
  }, []);
  useFocusEffect(
    useCallback(() => {
      setStatus('就绪');
      const subscription = AppState.addEventListener('change', (state) => {
        if (state !== 'active') {
          stop();
          setStatus('已停止');
        }
      });
      return () => {
        stop();
        subscription.remove();
      };
    }, [stop]),
  );

  async function start() {
    stop();
    const run = generation.current;
    const chunks = planChunks(config);
    setText('');
    setStatus('等待回复');
    let pulses: number;
    try {
      pulses = await debugReplyHaptics(
        chunks.map((chunk) => chunk.at),
        config,
      );
    } catch {
      setStatus('触感调用失败，请安装最新原生构建');
      return;
    }
    if (generation.current !== run) return;
    timers.current = chunks.map((chunk, index) =>
      setTimeout(() => {
        setText(reply.slice(0, chunk.length));
        setStatus(
          index === chunks.length - 1
            ? `完成 · ${pulses} 次触感`
            : `正在回复 · 本轮 ${pulses} 次触感`,
        );
      }, chunk.at),
    );
  }

  const row = (control: (typeof controls)[number]) => ({
    id: control.key,
    title: control.title,
    value: String(config[control.key]),
    action: true,
  });

  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={[
        {
          id: 'preview',
          header: '离线触感试验',
          footer:
            '由 native 按与聊天相同的规则计算并播放 Core Haptics。模拟器没有真实触感，请在 iPhone 上比较。',
          rows: [
            { id: 'reply-haptics-status', title: status },
            { id: 'reply-haptics-text', title: text || '…' },
            {
              id: 'reply-haptics-start',
              title: '模拟发送',
              image: 'paperplane',
              action: true,
            },
            {
              id: 'reply-haptics-reroll',
              title: '换一个网络样本',
              action: true,
            },
            { id: 'reply-haptics-stop', title: '停止', action: true },
          ],
        },
        {
          id: 'haptic',
          header: '触感',
          footer:
            '聊天使用 ChatReplyPulses.Config 默认值；这里的修改只作用于试验。',
          rows: hapticControls.map(row),
        },
        { id: 'network', header: '网络节奏', rows: networkControls.map(row) },
        {
          id: 'reset',
          rows: [
            { id: 'reply-haptics-reset', title: '恢复默认参数', action: true },
          ],
        },
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'reply-haptics-start') {
          void start();
          return;
        }
        stop();
        setStatus('已停止');
        if (id === 'reply-haptics-reset') {
          setConfig(defaults);
          setStatus('就绪');
          return;
        }
        if (id === 'reply-haptics-reroll') {
          setConfig((current) => ({
            ...current,
            seed: Math.floor(Math.random() * 1e9),
          }));
          setStatus('已换网络样本');
          return;
        }
        const control = controls.find((control) => control.key === id);
        if (!control) return;
        ActionSheetIOS.showActionSheetWithOptions(
          {
            title: control.title,
            options: [...control.values.map(String), '取消'],
            cancelButtonIndex: control.values.length,
          },
          (index) => {
            if (index >= control.values.length) return;
            setConfig((current) => ({
              ...current,
              [control.key]: control.values[index],
            }));
          },
        );
      }}
    />
  );
}

export const ReplyHapticsPreviewScreen = definePage({
  id: 'reply-haptics-preview',
  title: '回复触感试验',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
