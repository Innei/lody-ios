import { providerCommand } from '@lody-ios/kit';
import type {
  ProviderReply,
  ProviderRequest,
} from '@lody/cloud-runtime/models/providers';
import { providerError } from '@/features/providers/provider-config';

export async function requestProvider(
  request: ProviderRequest,
): Promise<ProviderReply> {
  try {
    const result: unknown = JSON.parse(
      await providerCommand(JSON.stringify(request)),
    );
    if (!result || typeof result !== 'object' || Array.isArray(result))
      throw new Error('invalid_provider_response');
    return result as ProviderReply;
  } catch (cause) {
    throw new Error(providerError(cause, request.action === 'save'));
  }
}
