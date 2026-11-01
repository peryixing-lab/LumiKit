import { common } from '@kit.AbilityKit';
import { preferences, relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { validateBackupDocument } from './BackupValidation';

export class HistoryRecord {
  id: string = '';
  toolId: string = '';
  title: string = '';
  detail: string = '';
  createdAt: number = 0;
  outputPath: string = '';
}

export class BackupDocument {
  key: string = '';
  value: string = '';
}

export class LumiBackup {
  format: string = 'LumiKit.metadata';
  version: number = 1;
  createdAt: number = Date.now();
  documents: BackupDocument[] = [];
  history: HistoryRecord[] = [];
}

/** One database connection; writes are serialized and migrations are atomic. */
export class StorageService {
  private static store: relationalStore.RdbStore | undefined;
  private static settings: preferences.Preferences | undefined;
  private static initialization: Promise<void> | undefined;
  private static writes: Promise<void> = Promise.resolve();

  static async init(context: common.UIAbilityContext): Promise<void> {
    if (!StorageService.initialization) {
      StorageService.initialization = StorageService.initialize(context).catch((error: Error) => {
        StorageService.initialization = undefined;
        throw error;
      });
    }
    await StorageService.initialization;
  }

  private static async initialize(context: common.UIAbilityContext): Promise<void> {
    const store = await relationalStore.getRdbStore(context, {
      name: 'lumikit.db', securityLevel: relationalStore.SecurityLevel.S2
    });
    if (store.version > 1) { throw new Error('数据来自更新版本，请升级集萤后打开'); }
    if (store.version === 0) {
      await store.beginTransaction();
      try {
        await store.executeSql('CREATE TABLE IF NOT EXISTS documents (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)');
        await store.executeSql('CREATE TABLE IF NOT EXISTS history (id TEXT PRIMARY KEY, tool_id TEXT NOT NULL, title TEXT NOT NULL, detail TEXT NOT NULL, created_at INTEGER NOT NULL, output_path TEXT NOT NULL)');
        await store.executeSql('CREATE INDEX IF NOT EXISTS history_time ON history(created_at DESC)');
        store.version = 1;
        await store.commit();
      } catch (error) {
        await store.rollBack();
        throw new Error('本地数据库初始化失败');
      }
    }
    StorageService.store = store;
    StorageService.settings = await preferences.getPreferences(context, 'lumikit_settings');
  }

  private static database(): relationalStore.RdbStore {
    if (!StorageService.store) { throw new Error('本地数据库尚未就绪'); }
    return StorageService.store;
  }

  private static async write(operation: () => Promise<void>): Promise<void> {
    const next = StorageService.writes.then(operation);
    StorageService.writes = next.catch(() => {});
    await next;
  }

  static async getValue(key: string, fallback: string = ''): Promise<string> {
    await StorageService.writes;
    const rows = await StorageService.database().querySql('SELECT value FROM documents WHERE key = ?', [key]);
    try { return rows.goToFirstRow() ? rows.getString(0) : fallback; } finally { rows.close(); }
  }

  static async setValue(key: string, value: string): Promise<void> {
    await StorageService.write(async () => {
      await StorageService.database().insert('documents', { key: key, value: value, updated_at: Date.now() },
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    });
  }

  static async setValues(documents: BackupDocument[]): Promise<void> {
    await StorageService.write(async () => {
      const db = StorageService.database();
      await db.beginTransaction();
      try {
        for (const document of documents) {
          await db.insert('documents', { key: document.key, value: document.value, updated_at: Date.now() },
            relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        }
        await db.commit();
      } catch (error) {
        await db.rollBack();
        throw new Error('数据未能完整保存，原有数据已保留');
      }
    });
  }

  static async getSetting(key: string, fallback: string = ''): Promise<string> {
    if (!StorageService.settings) { throw new Error('设置尚未就绪'); }
    return await StorageService.settings.get(key, fallback) as string;
  }

  static async setSetting(key: string, value: string): Promise<void> {
    if (!StorageService.settings) { throw new Error('设置尚未就绪'); }
    await StorageService.settings.put(key, value);
    await StorageService.settings.flush();
  }

  static async addHistory(toolId: string, title: string, detail: string, outputPath: string = ''): Promise<void> {
    if (await StorageService.getSetting('historyEnabled', 'true') === 'false') { return; }
    await StorageService.write(async () => {
      await StorageService.database().insert('history', {
        id: util.generateRandomUUID(true), tool_id: toolId, title: title, detail: detail,
        created_at: Date.now(), output_path: outputPath
      });
    });
  }

  static async getHistory(): Promise<HistoryRecord[]> {
    await StorageService.writes;
    const rows = await StorageService.database().querySql('SELECT id, tool_id, title, detail, created_at, output_path FROM history ORDER BY created_at DESC LIMIT 500');
    const result: HistoryRecord[] = [];
    try {
      while (rows.goToNextRow()) {
        result.push({ id: rows.getString(0), toolId: rows.getString(1), title: rows.getString(2),
          detail: rows.getString(3), createdAt: rows.getDouble(4), outputPath: rows.getString(5) });
      }
    } finally { rows.close(); }
    return result;
  }

  static async clearHistory(): Promise<void> {
    await StorageService.write(async () => { await StorageService.database().executeSql('DELETE FROM history'); });
  }

  static async exportBackup(): Promise<string> {
    await StorageService.writes;
    const backup = new LumiBackup();
    const rows = await StorageService.database().querySql("SELECT key, value FROM documents WHERE key NOT IN ('workspace', 'tasks', 'inventory.reminders', 'file.sessions', 'workbench.sessions') AND key NOT LIKE 'developer.draft.%'");
    try {
      while (rows.goToNextRow()) { backup.documents.push({ key: rows.getString(0), value: rows.getString(1) }); }
    } finally { rows.close(); }
    backup.history = await StorageService.getHistory();
    const content = JSON.stringify(backup, null, 2);
    if (new util.TextEncoder().encodeInto(content).length > 4 * 1024 * 1024) {
      throw new Error('数据备份超过当前 4 MB 上限，请先分别导出分析项目或表单回答');
    }
    return content;
  }

  static async restoreBackup(content: string, localDocuments: BackupDocument[] = []): Promise<void> {
    if (content.length > 4 * 1024 * 1024 || new util.TextEncoder().encodeInto(content).length > 4 * 1024 * 1024) {
      throw new Error('备份文件超过 4 MB，请拆分或精简后恢复');
    }
    const backup = JSON.parse(content) as LumiBackup;
    if (!backup || backup.format !== 'LumiKit.metadata' || backup.version !== 1 || !Array.isArray(backup.documents) ||
      backup.documents.length > 10000 || !Array.isArray(backup.history) || backup.history.length > 10000) {
      throw new Error('这不是支持的集萤数据备份');
    }
    for (const document of backup.documents) {
      if (!document || typeof document.key !== 'string' || typeof document.value !== 'string' || document.key.length > 200) {
        throw new Error('备份中的数据格式无效');
      }
      if (!validateBackupDocument(document.key, document.value)) { throw new Error('备份中的数据结构无效或包含不支持的模块'); }
    }
    await StorageService.write(async () => {
      const db = StorageService.database();
      await db.beginTransaction();
      try {
        for (const document of backup.documents) {
          // Metadata backups cannot replace the index of physical files on this device.
          if (document.key === 'workspace') { continue; }
          await db.insert('documents', { key: document.key, value: document.value, updated_at: Date.now() },
            relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        }
        for (const local of localDocuments) {
          await db.insert('documents', { key: local.key, value: local.value, updated_at: Date.now() }, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        }
        for (const record of backup.history) {
          if (typeof record.id !== 'string' || typeof record.toolId !== 'string' ||
            typeof record.title !== 'string' || typeof record.detail !== 'string' ||
            typeof record.createdAt !== 'number' || typeof record.outputPath !== 'string') {
            throw new Error('备份中的历史格式无效');
          }
          await db.insert('history', { id: record.id, tool_id: record.toolId, title: record.title,
            detail: record.detail, created_at: record.createdAt, output_path: record.outputPath },
            relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        }
        await db.commit();
      } catch (error) {
        await db.rollBack();
        throw new Error('备份恢复失败，原有数据已保留');
      }
    });
  }
}
