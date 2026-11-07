import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { StorageService } from './StorageService';

class LumiFileFlowReference { finalPath: string = ''; }

export interface TextFileResult { name: string; content: string; }
export interface WorkspaceFile {
  id: string;
  name: string;
  path: string;
  size: number;
  mime: string;
  createdAt: number;
  trashedAt?: number;
  collectionId?: string;
  sourcePaths?: string[];
  role?: string;
  tags?: string[];
  pageCount?: number;
}

/** All imported documents become private copies. Picker URIs are never persisted. */
export class FileService {
  static readonly MAX_TEXT_BYTES: number = 4 * 1024 * 1024;
  static readonly MAX_FILE_BYTES: number = 100 * 1024 * 1024;
  private static counter: number = 0;
  private static catalogWrites: Promise<void> = Promise.resolve();

  static directory(ctx: common.UIAbilityContext): string {
    const path = ctx.filesDir + '/workspace';
    if (!fs.accessSync(path)) { fs.mkdirSync(path, true); }
    return path;
  }

  static cleanName(name: string): string {
    return name.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_').slice(0, 120) || 'document';
  }

  static outputPath(ctx: common.UIAbilityContext, name: string): string {
    FileService.counter++;
    return FileService.directory(ctx) + '/' + Date.now().toString() + '_' + FileService.counter.toString() + '_' + FileService.cleanName(name);
  }

  static isOwnedPath(ctx: common.UIAbilityContext, path: string): boolean {
    const prefix = ctx.filesDir + '/workspace/';
    if (typeof path !== 'string' || !path.startsWith(prefix)) { return false; }
    const name = path.substring(prefix.length);
    return name.length > 0 && name !== '.' && name !== '..' && !name.includes('/') && !name.includes('\\') && !name.includes('\u0000');
  }

  static assertOwned(ctx: common.UIAbilityContext, path: string): void {
    if (!FileService.isOwnedPath(ctx, path) || !fs.accessSync(path)) { throw new Error('工作区文件不存在，请重新导入原文件'); }
    const stat = fs.lstatSync(path);
    if (!stat.isFile() || stat.isSymbolicLink()) { throw new Error('工作区文件路径无效，请重新导入'); }
  }

  static async list(ctx: common.UIAbilityContext, includeTrash: boolean = false): Promise<WorkspaceFile[]> {
    const data = await StorageService.getValue('workspace', '[]');
    const list = JSON.parse(data) as WorkspaceFile[];
    if (!Array.isArray(list)) { throw new Error('工作区索引无效'); }
    const seen = new Set<string>();
    return list.filter((file: WorkspaceFile) => {
      if (file === null || typeof file !== 'object' || typeof file.name !== 'string' || typeof file.id !== 'string' ||
        !FileService.isOwnedPath(ctx, file.path) || seen.has(file.path)) { return false; }
      if (!includeTrash && file.trashedAt) { return false; }
      try { FileService.assertOwned(ctx, file.path); seen.add(file.path); return true; } catch (_) { return false; }
    }).map((file: WorkspaceFile) => ({ id: file.path.substring(file.path.lastIndexOf('/') + 1), name: FileService.cleanName(file.name), path: file.path,
      size: fs.statSync(file.path).size, mime: FileService.mime(file.name), createdAt: typeof file.createdAt === 'number' ? file.createdAt : 0,
      trashedAt: file.trashedAt || 0, collectionId: file.collectionId || '', sourcePaths: file.sourcePaths || [],
      role: file.role || '', tags: file.tags || [], pageCount: file.pageCount || 0 } as WorkspaceFile));
  }

  static async register(ctx: common.UIAbilityContext, path: string, name: string): Promise<WorkspaceFile> {
    FileService.assertOwned(ctx, path);
    const file: WorkspaceFile = {
      id: path.substring(path.lastIndexOf('/') + 1), name: FileService.cleanName(name), path: path,
      size: fs.statSync(path).size, mime: FileService.mime(name), createdAt: Date.now()
    };
    const write = FileService.catalogWrites.then(async () => {
      const list = (await FileService.list(ctx, true)).filter((entry: WorkspaceFile) => entry.path !== path);
      list.unshift(file);
      await StorageService.setValue('workspace', JSON.stringify(list));
    });
    FileService.catalogWrites = write.catch(() => {});
    await write;
    return file;
  }

  static async readText(ctx: common.UIAbilityContext, path: string): Promise<string> {
    FileService.assertOwned(ctx, path);
    if ((await fs.stat(path)).size > FileService.MAX_TEXT_BYTES) { throw new Error('文本导入上限为 4 MB，请拆分后再处理'); }
    return (await fs.readText(path)).replace(/^\uFEFF/, '');
  }

  static async pickFiles(ctx: common.UIAbilityContext, filters: string[] = [], max: number = 20): Promise<WorkspaceFile[]> {
    const view = new picker.DocumentViewPicker(ctx);
    const uris = await view.select({ fileSuffixFilters: filters, maxSelectNumber: max });
    return FileService.importUris(ctx, uris);
  }

  static async importUris(ctx: common.UIAbilityContext, uris: string[], maxBytes: number = FileService.MAX_FILE_BYTES): Promise<WorkspaceFile[]> {
    if (uris.length > 20) { throw new Error('一次最多导入 20 个文件'); }
    const results: WorkspaceFile[] = [];
    for (let i = 0; i < uris.length; i++) {
      const uri = uris[i];
      const name = FileService.cleanName(decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1).split('?')[0]));
      const source = await fs.open(uri, fs.OpenMode.READ_ONLY);
      const path = FileService.outputPath(ctx, name);
      try {
        if ((await fs.stat(source.fd)).size > maxBytes) { throw new Error('文件超过导入大小上限'); }
        await fs.copyFile(source.fd, path);
      } catch (error) {
        if (fs.accessSync(path)) { await fs.unlink(path); }
        throw new Error((error as Error).message || '导入文件失败，请重试');
      } finally { await fs.close(source); }
      results.push(await FileService.register(ctx, path, name));
    }
    return results;
  }

  static async pickText(ctx: common.UIAbilityContext, filters: string[] = ['文本与数据|.txt,.md,.csv,.json,.xml']): Promise<TextFileResult> {
    const files = await FileService.pickFiles(ctx, filters, 1);
    if (files.length === 0) { throw new Error('已取消选择文件'); }
    const file = files[0];
    if (file.size > FileService.MAX_TEXT_BYTES) { throw new Error('文本导入上限为 4 MB，请拆分后再处理'); }
    const content = await FileService.readText(ctx, file.path);
    return { name: file.name, content: content.replace(/^\uFEFF/, '') };
  }

  static async writeText(ctx: common.UIAbilityContext, name: string, content: string): Promise<string> {
    const path = FileService.outputPath(ctx, name);
    const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { await fs.write(file.fd, content); } finally { await fs.close(file); }
    await FileService.register(ctx, path, name);
    return path;
  }

  static async exportFile(ctx: common.UIAbilityContext, path: string, name: string): Promise<string> {
    FileService.assertOwned(ctx, path);
    const uris = await new picker.DocumentViewPicker(ctx).save({ newFileNames: [FileService.cleanName(name)] });
    if (uris.length === 0) { throw new Error('已取消导出，结果仍保存在工作区'); }
    const target = await fs.open(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { await fs.copyFile(path, target.fd); } finally { await fs.close(target); }
    return uris[0];
  }

  static async exportText(ctx: common.UIAbilityContext, name: string, content: string): Promise<string> {
    const path = await FileService.writeText(ctx, name, content);
    return FileService.exportFile(ctx, path, name);
  }

  static async share(ctx: common.UIAbilityContext, path: string, name: string): Promise<void> {
    FileService.assertOwned(ctx, path);
    const lower = (name || '').toLowerCase();
    let shareUtd: string = uniformTypeDescriptor.UniformDataType.FILE;
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      shareUtd = 'general.markdown';
      try {
        const resolved = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension('.md');
        if (resolved && resolved.trim().length > 0) { shareUtd = resolved; }
      } catch (_) {}
    } else if (lower.endsWith('.txt')) {
      shareUtd = 'general.plain-text';
    }
    const data = new systemShare.SharedData({ utd: shareUtd, uri: fileUri.getUriFromPath(path), title: name });
    await new systemShare.ShareController(data).show(ctx, { previewMode: systemShare.SharePreviewMode.DEFAULT, selectionMode: systemShare.SelectionMode.SINGLE });
  }

  static async updateDetails(ctx: common.UIAbilityContext, file: WorkspaceFile): Promise<void> {
    FileService.assertOwned(ctx, file.path);
    const snapshot = JSON.parse(JSON.stringify(file)) as WorkspaceFile;
    const write = FileService.catalogWrites.then(async () => {
      const list = await FileService.list(ctx, true);
      const current = list.find((entry: WorkspaceFile) => entry.path === snapshot.path);
      if (!current) { throw new Error('文件已移除'); }
      // Keep stable paths and original extension so all attachments and history remain valid.
      const extension = current.name.includes('.') ? '.' + current.name.split('.').pop() : '';
      if (extension && !snapshot.name.toLowerCase().endsWith(extension.toLowerCase())) { snapshot.name += extension; }
      current.name = FileService.cleanName(snapshot.name);
      current.collectionId = snapshot.collectionId || '';
      current.tags = (snapshot.tags || []).map((tag: string) => tag.trim().slice(0, 24)).filter((tag: string, i: number, all: string[]) => !!tag && all.indexOf(tag) === i).slice(0, 10);
      current.sourcePaths = snapshot.sourcePaths || [];
      current.role = snapshot.role || '';
      current.pageCount = snapshot.pageCount || 0;
      await StorageService.setValue('workspace', JSON.stringify(list));
    });
    FileService.catalogWrites = write.catch(() => {}); await write;
  }
  private static async assertUnreferenced(path: string): Promise<void> {
    const token = JSON.stringify(path);
    if ((await StorageService.getValue('material.packs', '[]')).includes(token)) {
      throw new Error('此文件已关联材料包，请先在材料清单中解除绑定');
    }
    for (const key of ['inventory.items', 'forms.responses', 'forms.autodraft']) {
      if ((await StorageService.getValue(key, 'null')).includes(token)) { throw new Error('此文件已关联物品或表单，请先解除附件关联'); }
    }
    const flows = JSON.parse(await StorageService.getValue('workbench.sessions', '[]')) as Object[];
    if (flows.some((entry: Object) => JSON.stringify(entry).includes(token) && !(entry as LumiFileFlowReference).finalPath)) {
      throw new Error('此文件属于未完成流程，请先完成或移除该流程记录');
    }
    if ((await StorageService.getValue('file.sessions', '[]')).includes(token)) { throw new Error('此文件属于工具草稿，请先继续处理或清除草稿'); }
  }
  static async remove(ctx: common.UIAbilityContext, file: WorkspaceFile): Promise<void> {
    await FileService.setTrash(ctx, file, true);
  }
  static async setTrash(ctx: common.UIAbilityContext, file: WorkspaceFile, trashed: boolean): Promise<void> {
    const write = FileService.catalogWrites.then(async () => {
      FileService.assertOwned(ctx, file.path);
      if (trashed) { await FileService.assertUnreferenced(file.path); }
      const list = await FileService.list(ctx, true);
      const current = list.find((entry: WorkspaceFile) => entry.path === file.path);
      if (!current) { throw new Error('文件已移除'); }
      current.trashedAt = trashed ? Date.now() : 0;
      await StorageService.setValue('workspace', JSON.stringify(list));
    });
    FileService.catalogWrites = write.catch(() => {}); await write;
  }
  static async deletePermanently(ctx: common.UIAbilityContext, file: WorkspaceFile): Promise<void> {
    const write = FileService.catalogWrites.then(async () => {
      await FileService.assertUnreferenced(file.path);
      const list = await FileService.list(ctx, true);
      const current = list.find((entry: WorkspaceFile) => entry.path === file.path);
      if (!current?.trashedAt) { throw new Error('请先将文件移入回收站'); }
      // Remove the index first. A filesystem failure leaves an unindexed copy, never a dangling live attachment.
      await StorageService.setValue('workspace', JSON.stringify(list.filter((entry: WorkspaceFile) => entry.path !== file.path)));
      try { await fs.unlink(file.path); }
      catch (error) { await StorageService.setValue('workspace', JSON.stringify(list)); throw new Error((error as Error).message || '永久删除未完成'); }
    });
    FileService.catalogWrites = write.catch(() => {}); await write;
  }

  static mime(name: string): string {
    const ext = name.split('.').pop()?.toLowerCase() || '';
    if (ext === 'pdf') { return 'application/pdf'; }
    if (ext === 'jpg' || ext === 'jpeg') { return 'image/jpeg'; }
    if (['png', 'webp', 'heic', 'gif'].includes(ext)) { return 'image/' + ext; }
    if (ext === 'lumibak') { return 'application/octet-stream'; }
    if (ext === 'xlsx') { return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'; }
    if (ext === 'json') { return 'application/json'; }
    if (ext === 'csv') { return 'text/csv'; }
    if (ext === 'zip') { return 'application/zip'; }
    if (ext === 'md' || ext === 'markdown') { return 'text/markdown'; }
    return 'text/plain';
  }

  static sizeLabel(size: number): string {
    return size >= 1024 * 1024 ? (size / (1024 * 1024)).toFixed(1) + ' MB' : (size / 1024).toFixed(1) + ' KB';
  }
}
