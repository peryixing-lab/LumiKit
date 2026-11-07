import { StorageService } from '../../core/StorageService';
import { LumiMaterialPack, LumiMaterialTemplate, validMaterialPack, validMaterialTemplate } from './MaterialPackModels';

export class LumiMaterialPackStore {
  private static writes: Promise<void> = Promise.resolve();
  private static sequence: number = 0;

  static newId(): string { return Date.now().toString() + '_' + (++LumiMaterialPackStore.sequence).toString(); }

  private static async update(operation: () => Promise<void>): Promise<void> {
    const next = LumiMaterialPackStore.writes.then(operation);
    LumiMaterialPackStore.writes = next.catch(() => {});
    await next;
  }

  private static async readPacks(): Promise<LumiMaterialPack[]> {
    const packs = JSON.parse(await StorageService.getValue('material.packs', '[]')) as LumiMaterialPack[];
    if (!Array.isArray(packs) || packs.length > 30 || !packs.every(validMaterialPack) ||
      new Set(packs.map((pack: LumiMaterialPack): string => pack.id)).size !== packs.length) { throw new Error('材料包无法读取，已有资料保留'); }
    return packs;
  }

  static async packs(): Promise<LumiMaterialPack[]> {
    await LumiMaterialPackStore.writes;
    return LumiMaterialPackStore.readPacks();
  }

  static async putPack(pack: LumiMaterialPack): Promise<void> {
    const snapshot = JSON.parse(JSON.stringify(pack)) as LumiMaterialPack;
    if (!validMaterialPack(snapshot)) { throw new Error('请检查材料名称、格式和大小要求；每包最多 20 项'); }
    await LumiMaterialPackStore.update(async () => {
      const packs = (await LumiMaterialPackStore.readPacks()).filter((entry: LumiMaterialPack): boolean => entry.id !== snapshot.id);
      if (packs.length >= 30) { throw new Error('最多保存 30 个材料包，请先移除不再需要的清单'); }
      await StorageService.setValue('material.packs', JSON.stringify([snapshot].concat(packs)));
    });
  }

  static async deletePack(id: string): Promise<void> {
    await LumiMaterialPackStore.update(async () => {
      const packs = (await LumiMaterialPackStore.readPacks()).filter((pack: LumiMaterialPack): boolean => pack.id !== id);
      await StorageService.setValue('material.packs', JSON.stringify(packs));
    });
  }

  private static async readTemplates(): Promise<LumiMaterialTemplate[]> {
    const templates = JSON.parse(await StorageService.getValue('material.templates', '[]')) as LumiMaterialTemplate[];
    if (!Array.isArray(templates) || templates.length > 30 || !templates.every(validMaterialTemplate) ||
      new Set(templates.map((template: LumiMaterialTemplate): string => template.id)).size !== templates.length) { throw new Error('材料清单模板无法读取'); }
    return templates;
  }

  static async templates(): Promise<LumiMaterialTemplate[]> {
    await LumiMaterialPackStore.writes;
    return LumiMaterialPackStore.readTemplates();
  }

  static async putTemplate(template: LumiMaterialTemplate): Promise<void> {
    const snapshot = JSON.parse(JSON.stringify(template)) as LumiMaterialTemplate;
    if (!validMaterialTemplate(snapshot)) { throw new Error('模板至少包含一项材料，只保存要求，不保存关联文件'); }
    await LumiMaterialPackStore.update(async () => {
      const templates = (await LumiMaterialPackStore.readTemplates()).filter((entry: LumiMaterialTemplate): boolean => entry.id !== snapshot.id);
      if (templates.length >= 30) { throw new Error('最多保存 30 个清单模板'); }
      await StorageService.setValue('material.templates', JSON.stringify([snapshot].concat(templates)));
    });
  }

  static async deleteTemplate(id: string): Promise<void> {
    await LumiMaterialPackStore.update(async () => {
      const templates = (await LumiMaterialPackStore.readTemplates()).filter((template: LumiMaterialTemplate): boolean => template.id !== id);
      await StorageService.setValue('material.templates', JSON.stringify(templates));
    });
  }
}
