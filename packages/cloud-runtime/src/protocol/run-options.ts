// The complete selected map includes ordinary options and Role pins. Preserve both.
export function supportsRunConfigOptions(
  value: unknown,
  maximum = 128,
): boolean {
  if (value === undefined) return true;
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const entries = Object.entries(value);
  return (
    entries.length <= maximum &&
    entries.every(
      ([id, option]) =>
        id.length > 0 &&
        id.length <= 128 &&
        !/(?:api[_-]?key|auth|bearer|credential|password|passwd|secret|token)/i.test(
          id,
        ) &&
        (typeof option === 'boolean' ||
          (typeof option === 'string' &&
            option.length > 0 &&
            option.length <= 512)),
    )
  );
}
