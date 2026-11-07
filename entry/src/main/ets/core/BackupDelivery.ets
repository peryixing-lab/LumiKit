import { common } from '@kit.AbilityKit';
import { FileService, WorkspaceFile } from './FileService';
import { StorageService } from './StorageService';

export class LumiBackupDelivery {
  path: string = '';
  name: string = '';
  generatedAt: number = 0;
  exportedAt: number = 0;
  lastExportedAt: number = 0;
  lastExportedName: string = '';
}

/** Generation and picker export are separate durable milestones. */
export class BackupDelivery {
  static async load(): Promise<LumiBackupDelivery> {
    const content = await StorageService.getSetting('backup.delivery', '');
    if (!content) { return new LumiBackupDelivery(); }
    try {
      const state = JSON.parse(content) as LumiBackupDelivery;
      if (state && typeof state.path === 'string' && typeof state.name === 'string' &&
        Number.isFinite(state.generatedAt) && state.generatedAt > 0 && Number.isFinite(state.exportedAt) && state.exportedAt >= 0 &&
        Number.isFinite(state.lastExportedAt) && state.lastExportedAt >= 0 && typeof state.lastExportedName === 'string') {
        return state;
      }
    } catch (_) {}
    return new LumiBackupDelivery();
  }

  static async generated(file: WorkspaceFile): Promise<LumiBackupDelivery> {
    const previous = await BackupDelivery.load();
    const state = new LumiBackupDelivery();
    state.path = file.path; state.name = file.name; state.generatedAt = Date.now();
    state.lastExportedAt = previous.lastExportedAt; state.lastExportedName = previous.lastExportedName;
    await StorageService.setSetting('backup.delivery', JSON.stringify(state));
    return state;
  }

  static async exportPending(ctx: common.UIAbilityContext, state: LumiBackupDelivery): Promise<LumiBackupDelivery> {
    if (!state.path) { throw new Error('请先生成完整备份'); }
    FileService.assertOwned(ctx, state.path);
    await FileService.exportFile(ctx, state.path, state.name);
    const completed = JSON.parse(JSON.stringify(state)) as LumiBackupDelivery;
    completed.exportedAt = Date.now(); completed.lastExportedAt = completed.exportedAt; completed.lastExportedName = state.name;
    await StorageService.setSetting('backup.delivery', JSON.stringify(completed));
    return completed;
  }
}
