let id = '';
const listeners = new Set<() => void>();

export function setForegroundSession(next: string) {
  if (id === next) return;
  id = next;
  listeners.forEach((listener) => listener());
}

export function getForegroundSession() {
  return id;
}

export function subscribeForegroundSession(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}
