import { remoteSettingsRaw } from '@lody-ios/kit';
import type {
  RemoteSetting,
  SettingsRequest,
} from '@lody/cloud-runtime/models/settings';
import { t } from '../lib/i18n/index.ts';

export async function requestSettings(
  request: SettingsRequest,
): Promise<RemoteSetting[]> {
  try {
    const result: unknown = JSON.parse(
      await remoteSettingsRaw(JSON.stringify(request)),
    );
    if (
      !Array.isArray(result) ||
      result.some(
        (item) =>
          !item ||
          item.kind !== request.kind ||
          typeof item.id !== 'string' ||
          typeof item.name !== 'string',
      )
    )
      throw new Error('invalid_setting');
    return result;
  } catch (error) {
    const message = String(error);
    if (message.includes('setting_read_only'))
      throw new Error(t('settings.remote.readOnly'));
    if (message.includes('setting_conflict'))
      throw new Error(t('settings.remote.conflict'));
    if (message.includes('setting_duplicate'))
      throw new Error(t('settings.remote.duplicate'));
    throw new Error(
      t(
        request.edit
          ? 'settings.remote.saveFailed'
          : 'settings.remote.loadFailed',
      ),
    );
  }
}
