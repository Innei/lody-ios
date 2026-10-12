export const outboxInflight = new Set<string>();

export async function waitForSendReceipt(
  request: Promise<string>,
  timeoutMs = 35000,
): Promise<string> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      request,
      new Promise<string>((resolve) => {
        timer = setTimeout(
          () =>
            resolve(
              JSON.stringify({
                state: 'unknown',
                reason: 'confirmation_timeout',
              }),
            ),
          timeoutMs,
        );
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}
