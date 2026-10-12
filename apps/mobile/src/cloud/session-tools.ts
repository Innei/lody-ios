import { sessionTools as nativeSessionTools } from '@lody-ios/kit';
import type {
  SessionToolsRequest,
  SessionToolsResult,
} from '@lody/cloud-runtime/models/session-tools';

export type SessionToolsSource = (
  request: SessionToolsRequest,
) => Promise<SessionToolsResult>;

export const requestSessionTools: SessionToolsSource = async (request) => {
  const result: SessionToolsResult = JSON.parse(
    await nativeSessionTools(JSON.stringify(request)),
  );
  if (!result || result.action !== request.action)
    throw new Error('invalid_session_tools_response');
  if (result.action === 'fork-options') {
    if (
      typeof result.shared !== 'boolean' ||
      typeof result.newWorktree !== 'boolean' ||
      typeof result.targetSessionId !== 'string' ||
      !result.targetSessionId
    )
      throw new Error('invalid_session_tools_response');
  } else if (result.action === 'fork' || result.action === 'fork-status') {
    const target =
      request.action === 'fork'
        ? request.spec.targetSessionId
        : (request as Extract<SessionToolsRequest, { action: 'fork-status' }>)
            .targetSessionId;
    if (
      !result.fork ||
      result.fork.targetSessionId !== target ||
      ![
        'preparing',
        'completed',
        'failed',
        'confirmation-required',
        'unknown',
      ].includes(result.fork.state)
    )
      throw new Error('invalid_session_tools_response');
  } else if (!('saved' in result) || result.saved !== true)
    throw new Error('invalid_session_tools_response');
  return result;
};
