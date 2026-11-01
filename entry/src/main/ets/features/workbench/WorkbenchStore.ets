import { StorageService } from '../../core/StorageService';
import { LumiCollection, LumiFlowRecipe, LumiFlowSession, LumiFileSession, validCollection, validFlowRecipe, validFileSession, validFlowSession } from './WorkbenchModels';

/** Serialize read-modify-write operations as well as database writes. */
export class WorkbenchStore {
  private static writes: Promise<void> = Promise.resolve();
  private static sequence: number = 0;
  static newId(): string { return Date.now().toString() + '_' + (++WorkbenchStore.sequence).toString(); }
  private static async update(operation: () => Promise<void>): Promise<void> {
    const next = WorkbenchStore.writes.then(operation);
    WorkbenchStore.writes = next.catch(() => {});
    await next;
  }
  static async collections(): Promise<LumiCollection[]> {
    const entries = JSON.parse(await StorageService.getValue('workspace.collections', '[]')) as LumiCollection[];
    if (!Array.isArray(entries) || !entries.every(validCollection)) { throw new Error('资料集合无法读取'); }
    return entries;
  }
  static async putCollection(entry: LumiCollection): Promise<void> {
    if (!validCollection(entry)) { throw new Error('请输入 1–80 字的集合名称'); }
    await WorkbenchStore.update(async () => {
      const entries = await WorkbenchStore.collections();
      await StorageService.setValue('workspace.collections', JSON.stringify([entry].concat(entries.filter((item: LumiCollection) => item.id !== entry.id))));
    });
  }
  static async recipes(): Promise<LumiFlowRecipe[]> {
    const entries = JSON.parse(await StorageService.getValue('workbench.recipes', '[]')) as LumiFlowRecipe[];
    if (!Array.isArray(entries) || !entries.every(validFlowRecipe)) { throw new Error('流程预设无法读取'); }
    return entries;
  }
  static async putRecipe(entry: LumiFlowRecipe): Promise<void> {
    if (!validFlowRecipe(entry)) { throw new Error('请检查流程名称、大小和质量设置'); }
    await WorkbenchStore.update(async () => {
      const entries = [entry].concat((await WorkbenchStore.recipes()).filter((item: LumiFlowRecipe) => item.id !== entry.id));
      if (entries.length > 30) { throw new Error('最多保存 30 个流程，请先删除不再使用的流程'); }
      await StorageService.setValue('workbench.recipes', JSON.stringify(entries));
    });
  }
  static async deleteRecipe(id: string): Promise<void> {
    await WorkbenchStore.update(async () => { await StorageService.setValue('workbench.recipes', JSON.stringify((await WorkbenchStore.recipes()).filter((entry: LumiFlowRecipe) => entry.id !== id))); });
  }
  static async fileSessions(): Promise<LumiFileSession[]> {
    const entries = JSON.parse(await StorageService.getValue('file.sessions', '[]')) as LumiFileSession[];
    return Array.isArray(entries) ? entries.filter(validFileSession).sort((a: LumiFileSession, b: LumiFileSession) => b.updatedAt - a.updatedAt) : [];
  }
  static async putFileSession(session: LumiFileSession): Promise<void> {
    const snapshot = JSON.parse(JSON.stringify(session)) as LumiFileSession;
    await WorkbenchStore.update(async () => {
      const entries = (await WorkbenchStore.fileSessions()).filter((entry: LumiFileSession) => entry.toolId !== snapshot.toolId);
      if (snapshot.paths.length) { entries.unshift(snapshot); }
      await StorageService.setValue('file.sessions', JSON.stringify(entries.slice(0, 25)));
    });
  }
  static async flows(): Promise<LumiFlowSession[]> {
    const entries = JSON.parse(await StorageService.getValue('workbench.sessions', '[]')) as LumiFlowSession[];
    if (!Array.isArray(entries) || !entries.every(validFlowSession)) { throw new Error('流程记录无法读取'); }
    return entries;
  }
  static async putFlow(session: LumiFlowSession): Promise<void> {
    if (!validFlowSession(session)) { throw new Error('流程状态无效，未覆盖已保存的进度'); }
    const snapshot = JSON.parse(JSON.stringify(session)) as LumiFlowSession;
    await WorkbenchStore.update(async () => {
      const entries = (await WorkbenchStore.flows()).filter((entry: LumiFlowSession) => entry.id !== snapshot.id);
      if (entries.length >= 100) { throw new Error('流程记录已满，请先移除已完成的记录'); }
      await StorageService.setValue('workbench.sessions', JSON.stringify([snapshot].concat(entries)));
    });
  }
  static async deleteFlow(id: string): Promise<void> {
    await WorkbenchStore.update(async () => { await StorageService.setValue('workbench.sessions', JSON.stringify((await WorkbenchStore.flows()).filter((entry: LumiFlowSession) => entry.id !== id))); });
  }
}
