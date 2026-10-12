// Adapted from Lody OSS 987962e (AGPL-3.0-only).
/**
 * Minimal 5-field cron "next fire time" computer, no dependencies.
 *
 * Cron/ScheduleWakeup scheduled tasks only carry a cron expression (e.g. `39 11 3 7 *`
 * or `0 9 * * 1-5`) in their ACP tool response — no concrete timestamp. This resolves the
 * next fire time so the UI can show WHEN a pending task will trigger. Computed relative to
 * `fromMs`, so a recurring job always resolves to its next occurrence.
 *
 * Supports the standard field syntax the scheduling tools emit: `*`, single values,
 * ranges (`a-b`), a `/step` suffix on any of those (e.g. every-5), and comma lists of
 * those. Anything it can't parse returns undefined and the caller just omits the time.
 */

type CronField = {
  /** Whether the raw field was `*` (needed for the POSIX day-of-month/day-of-week rule). */
  star: boolean;
  /** Allowed values for this field. */
  values: Set<number>;
};

const FIELD_RANGES: Array<{ min: number; max: number }> = [
  { min: 0, max: 59 }, // minute
  { min: 0, max: 23 }, // hour
  { min: 1, max: 31 }, // day of month
  { min: 1, max: 12 }, // month
  { min: 0, max: 7 }, // day of week (0 and 7 = Sunday)
];

const MINUTE_MS = 60_000;
/** Bound the search so a never-matching expression (e.g. Feb 31) terminates. */
const MAX_LOOKAHEAD_MINUTES = 366 * 24 * 60;

function parseInteger(raw: string): number | null {
  return /^\d+$/.test(raw) ? Number.parseInt(raw, 10) : null;
}

/** Expand one comma-separated term (`*`, `a`, `a-b`, each optionally with a `/step`
 *  suffix) into `out`. */
function expandTerm(
  term: string,
  range: { min: number; max: number },
  out: Set<number>,
): boolean {
  const [rangePart, stepPart, ...rest] = term.split('/');
  if (rest.length > 0 || rangePart === undefined || rangePart === '')
    return false;

  let step = 1;
  if (stepPart !== undefined) {
    const parsed = parseInteger(stepPart);
    if (parsed === null || parsed < 1) return false;
    step = parsed;
  }

  let lo: number;
  let hi: number;
  if (rangePart === '*') {
    lo = range.min;
    hi = range.max;
  } else if (rangePart.includes('-')) {
    const [loRaw, hiRaw, ...more] = rangePart.split('-');
    if (more.length > 0 || loRaw === undefined || hiRaw === undefined)
      return false;
    const loParsed = parseInteger(loRaw);
    const hiParsed = parseInteger(hiRaw);
    if (loParsed === null || hiParsed === null) return false;
    lo = loParsed;
    hi = hiParsed;
  } else {
    const value = parseInteger(rangePart);
    if (value === null) return false;
    lo = value;
    // `a/n` means "from a to the max, every n"; a bare `a` is just that value.
    hi = stepPart !== undefined ? range.max : value;
  }

  if (lo < range.min || hi > range.max || lo > hi) return false;
  for (let value = lo; value <= hi; value += step) out.add(value);
  return true;
}

function parseCronField(
  raw: string,
  range: { min: number; max: number },
): CronField | null {
  const values = new Set<number>();
  for (const term of raw.split(',')) {
    if (!expandTerm(term, range, values)) return null;
  }
  if (values.size === 0) return null;
  return { star: raw === '*', values };
}

function matchesDayFields(
  dom: CronField,
  dow: CronField,
  dayOfMonth: number,
  jsDay: number,
): boolean {
  const domMatch = dom.values.has(dayOfMonth);
  // cron allows 0 or 7 for Sunday; jsDay is 0 (Sun) .. 6 (Sat).
  const dowMatch = dow.values.has(jsDay) || (jsDay === 0 && dow.values.has(7));
  // POSIX rule: when BOTH day-of-month and day-of-week are restricted, either match
  // fires; otherwise the (possibly wildcard) fields are AND-ed.
  if (!dom.star && !dow.star) return domMatch || dowMatch;
  return domMatch && dowMatch;
}

/** The wall-clock fields a cron matches against, read for a given instant. */
type WallClock = {
  minute: number;
  hour: number;
  month: number;
  day: number;
  weekday: number;
};

/**
 * Build a reader that returns an instant's wall-clock fields in `timeZone`, or undefined if
 * the zone is unusable. Cron is local-time to the machine that created it, so fire-time
 * resolution must read the candidate minute in THAT zone, not the viewer's browser zone.
 *
 * Works by computing the zone's UTC offset (via `Intl`) and shifting the epoch, then reading
 * `getUTC*`. The offset only changes at DST boundaries (whole hours), so it is recomputed
 * once per hour bucket and reused across the minute-by-minute scan — one `Intl` call per hour
 * of look-ahead instead of one per minute.
 */
function createZonedClockReader(
  timeZone: string,
): ((ms: number) => WallClock) | undefined {
  let formatter: Intl.DateTimeFormat;
  try {
    formatter = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    formatter.formatToParts(new Date(0)); // validate the zone up front
  } catch {
    return undefined;
  }

  const offsetMsAt = (ms: number): number => {
    const f: Record<string, string> = {};
    for (const part of formatter.formatToParts(new Date(ms))) {
      if (part.type !== 'literal') f[part.type] = part.value;
    }
    const wallAsUtc = Date.UTC(
      Number(f.year),
      Number(f.month) - 1,
      Number(f.day),
      Number(f.hour) % 24,
      Number(f.minute),
      Number(f.second),
    );
    return wallAsUtc - ms;
  };

  let cachedBucket: number | null = null;
  let offsetMs = 0;
  return (ms: number): WallClock => {
    const bucket = Math.floor(ms / 3_600_000);
    if (bucket !== cachedBucket) {
      offsetMs = offsetMsAt(ms);
      cachedBucket = bucket;
    }
    const shifted = new Date(ms + offsetMs);
    return {
      minute: shifted.getUTCMinutes(),
      hour: shifted.getUTCHours(),
      month: shifted.getUTCMonth() + 1,
      day: shifted.getUTCDate(),
      weekday: shifted.getUTCDay(),
    };
  };
}

/** Read an instant's wall-clock fields in the viewer's local zone (fallback when no TZ). */
function localClock(ms: number): WallClock {
  const date = new Date(ms);
  return {
    minute: date.getMinutes(),
    hour: date.getHours(),
    month: date.getMonth() + 1,
    day: date.getDate(),
    weekday: date.getDay(),
  };
}

/**
 * Next time (epoch ms) a 5-field cron expression fires strictly after `fromMs`.
 * Returns undefined for expressions this parser can't handle or that never fire
 * within a year.
 *
 * `timeZone` (IANA, e.g. `America/New_York`) is the zone the cron is interpreted in — the
 * machine that created the job. Cron carries no timezone, so without this the fields would be
 * matched in the viewer's local zone and the fire time would drift when the two differ. When
 * omitted or unusable, falls back to the local zone (previous behavior).
 */
export function nextCronFireMs(
  expression: string,
  fromMs: number,
  timeZone?: string,
): number | undefined {
  const parts = expression.trim().split(/\s+/);
  if (parts.length !== 5) return undefined;

  const fields = parts.map((part, index) =>
    parseCronField(part, FIELD_RANGES[index]!),
  );
  if (fields.some((field) => field === null)) return undefined;
  const [minute, hour, dom, month, dow] = fields as CronField[];

  const readClock =
    (timeZone ? createZonedClockReader(timeZone) : undefined) ?? localClock;

  // Start at the next whole minute after `fromMs`.
  let cursorMs = Math.ceil((fromMs + 1) / MINUTE_MS) * MINUTE_MS;
  for (
    let step = 0;
    step < MAX_LOOKAHEAD_MINUTES;
    step += 1, cursorMs += MINUTE_MS
  ) {
    const clock = readClock(cursorMs);
    if (!minute!.values.has(clock.minute)) continue;
    if (!hour!.values.has(clock.hour)) continue;
    if (!month!.values.has(clock.month)) continue;
    if (!matchesDayFields(dom!, dow!, clock.day, clock.weekday)) continue;
    return cursorMs;
  }
  return undefined;
}
