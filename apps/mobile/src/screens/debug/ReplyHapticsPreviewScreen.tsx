import { useCallback, useEffect, useRef, useState } from 'react';
import { ActionSheetIOS, AppState } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { NativeGroupedList, debugReplyImpact } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';

const defaults = {
  delay: 800,
  window: 5000,
  duration: 600,
  interval: 150,
  count: 3,
  intensity: 0.35,
  speed: 80,
  style: 'soft',
};
const controls = [
  { key: 'delay', title: '首字延迟（ms）', values: [0, 800, 2000, 4900, 6000] },
  {
    key: 'window',
    title: '发送后触发窗口（ms）',
    values: [1000, 3000, 5000, 10000],
  },
  {
    key: 'duration',
    title: '首字后震动时长（ms）',
    values: [300, 600, 1200, 3000],
  },
  { key: 'interval', title: '震动最短间隔（ms）', values: [80, 150, 250, 400] },
  { key: 'count', title: '最多震动次数', values: [1, 2, 3, 5, 10] },
  { key: 'intensity', title: '震动强度', values: [0.2, 0.35, 0.5, 0.75, 1] },
  {
    key: 'speed',
    title: '每两个字间隔（ms，0 为整段）',
    values: [0, 40, 80, 160, 300],
  },
  { key: 'style', title: '触感类型', values: ['soft', 'light', 'rigid'] },
] as const;
const reply =
  '收到，我正在为你整理这个想法。文字逐渐出现时，感受一下指尖轻轻的反馈。';

function View() {
  const colors = usePalette();
  const [config, setConfig] = useState(defaults);
  const [text, setText] = useState('点击模拟发送，感受回复开始出现时的触感。');
  const [status, setStatus] = useState('就绪');
  const [pulses, setPulses] = useState(0);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const generation = useRef(0);
  const active = useRef(false);
  const stop = useCallback(() => {
    generation.current++;
    active.current = false;
    clearTimeout(timer.current);
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

  // Fire after React commits the corresponding text update, never from a free-running pulse timer.
  useEffect(() => {
    if (!pulses || !active.current) return;
    const run = generation.current;
    void debugReplyImpact(config.style, config.intensity).catch(() => {
      if (generation.current !== run) return;
      stop();
      setStatus('触感调用失败，请安装最新原生构建');
    });
  }, [pulses, config.style, config.intensity, stop]);

  function start() {
    stop();
    active.current = true;
    const run = generation.current;
    const sentAt = performance.now();
    let firstAt: number | undefined;
    let lastPulse = -Infinity;
    let count = 0;
    let length = 0;
    setPulses(0);
    setText('');
    setStatus('等待回复');
    function tick() {
      if (generation.current !== run || AppState.currentState !== 'active')
        return;
      const now = performance.now();
      firstAt ??= now;
      length =
        config.speed === 0 ? reply.length : Math.min(reply.length, length + 2);
      setText(reply.slice(0, length));
      const eligible = firstAt - sentAt <= config.window;
      if (
        eligible &&
        now - firstAt <= config.duration &&
        count < config.count &&
        now - lastPulse >= config.interval
      ) {
        lastPulse = now;
        count++;
        setPulses(count);
      }
      if (length === reply.length) {
        setStatus(`完成 · ${count} 次触感`);
      } else {
        setStatus(
          eligible ? `正在回复 · ${count} 次触感` : '正在回复 · 超出触发窗口',
        );
        timer.current = setTimeout(tick, config.speed);
      }
    }
    timer.current = setTimeout(tick, config.delay);
  }

  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={[
        {
          id: 'preview',
          header: '离线触感试验',
          footer:
            '仅模拟正文输出，不发送云端消息。模拟器没有真实触感，请在 iPhone 上比较。',
          rows: [
            { id: 'reply-haptics-status', title: status },
            { id: 'reply-haptics-text', title: text || '…' },
            {
              id: 'reply-haptics-start',
              title: '模拟发送',
              image: 'paperplane',
              action: true,
            },
            { id: 'reply-haptics-stop', title: '停止', action: true },
          ],
        },
        {
          id: 'parameters',
          header: '参数',
          footer:
            '点按选择；修改参数会停止当前演示。不包含发送和完成时的震动。',
          rows: controls.map((control) => ({
            id: control.key,
            title: control.title,
            value: String(config[control.key]),
            action: true,
          })),
        },
        {
          id: 'reset',
          rows: [
            { id: 'reply-haptics-reset', title: '恢复默认参数', action: true },
          ],
        },
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'reply-haptics-start') {
          start();
          return;
        }
        stop();
        setStatus('已停止');
        if (id === 'reply-haptics-reset') {
          setConfig(defaults);
          setPulses(0);
          setStatus('就绪');
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
