import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { zlib } from '@kit.BasicServicesKit';
import { FileService, WorkspaceFile } from './FileService';

export class LumiBatchFailure {
  name: string = '';
  reason: string = '';
}

export class LumiBatchOutcome {
  succeeded: string[] = [];
  failed: LumiBatchFailure[] = [];
}

/** Names are independent from the stable internal paths; avoid collisions after sanitizing. */
export function batchFileNames(files: WorkspaceFile[]): string[] {
  const used = new Set<string>();
  return files.map((file: WorkspaceFile): string => {
    const sanitized = FileService.cleanName(file.name);
    const original = sanitized === '.' || sanitized === '..' ? 'document' : sanitized;
    const dot = original.lastIndexOf('.');
    const hasExtension = dot > 0 && original.length - dot <= 100;
    const stem = hasExtension ? original.substring(0, dot) : original;
    const extension = hasExtension ? original.substring(dot) : '';
    let name = original;
    let sequence = 1;
    while (used.has(name.toLowerCase())) {
      const suffix = '_' + (++sequence).toString();
      name = stem.slice(0, Math.max(1, 120 - suffix.length - extension.length)) + suffix + extension;
    }
    used.add(name.toLowerCase());
    return name;
  });
}

export function batchOutcomeLabel(outcome: LumiBatchOutcome): string {
  const summary = '成功 ' + outcome.succeeded.length.toString() + ' 个，未完成 ' + outcome.failed.length.toString() + ' 个';
  return summary + (outcome.failed.length ? '\n' + outcome.failed.map((failure: LumiBatchFailure): string => failure.name + '：' + failure.reason).join('\n') : '');
}

/** File bytes are always copied; no batch operation rewrites the original. */
export class BatchFileService {
  static readonly MAX_FILES: number = 100;
  static readonly MAX_TOTAL_BYTES: number = 500 * 1024 * 1024;
  private static sequence: number = 0;

  private static async checked(ctx: common.UIAbilityContext, files: WorkspaceFile[]): Promise<WorkspaceFile[]> {
    if (!files.length) { throw new Error('请先选择文件'); }
    if (files.length > BatchFileService.MAX_FILES) { throw new Error('一次最多处理 100 个文件'); }
    const active = await FileService.list(ctx);
    const checked: WorkspaceFile[] = [];
    let total = 0;
    for (const selected of files) {
      const current = active.find((file: WorkspaceFile): boolean => file.path === selected.path);
      if (!current) { throw new Error(selected.name + ' 已移除，请重新选择'); }
      if (checked.some((file: WorkspaceFile): boolean => file.path === current.path)) { throw new Error('选择中包含重复文件'); }
      FileService.assertOwned(ctx, current.path);
      total += current.size;
      // Callers may supply an output name (for example a material checklist item).
      const snapshot = JSON.parse(JSON.stringify(current)) as WorkspaceFile;
      snapshot.name = FileService.cleanName(selected.name);
      checked.push(snapshot);
    }
    if (total > BatchFileService.MAX_TOTAL_BYTES) { throw new Error('批量交付文件总大小上限为 500 MB，请分批操作'); }
    return checked;
  }

  static async share(ctx: common.UIAbilityContext, files: WorkspaceFile[]): Promise<void> {
    const checked = await BatchFileService.checked(ctx, files);
    const names = batchFileNames(checked);
    const temporary = ctx.cacheDir + '/lumi_share_' + Date.now().toString() + '_' + (++BatchFileService.sequence).toString();
    fs.mkdirSync(temporary);
    let handedOff = false;
    try {
      for (let index = 0; index < checked.length; index++) { await fs.copyFile(checked[index].path, temporary + '/' + names[index]); }
      const data = new systemShare.SharedData({ utd: 'general.file', uri: fileUri.getUriFromPath(temporary + '/' + names[0]), title: names[0] });
      for (let index = 1; index < checked.length; index++) {
        data.addRecord({ utd: 'general.file', uri: fileUri.getUriFromPath(temporary + '/' + names[index]), title: names[index] });
      }
      // Receivers can read URIs after show() settles. Keep handed-off copies in cache
      // until the user clears temporary files; deleting here could break a delivery.
      handedOff = true;
      await new systemShare.ShareController(data).show(ctx, {
        previewMode: systemShare.SharePreviewMode.DEFAULT, selectionMode: systemShare.SelectionMode.BATCH
      });
    } finally {
      if (!handedOff && fs.accessSync(temporary)) { try { await fs.rmdir(temporary); } catch (_) {} }
    }
  }

  static async exportFiles(ctx: common.UIAbilityContext, files: WorkspaceFile[]): Promise<void> {
    const checked = await BatchFileService.checked(ctx, files);
    const names = batchFileNames(checked);
    const uris = await new picker.DocumentViewPicker(ctx).save({ newFileNames: names });
    if (!uris.length) { throw new Error('已取消导出，文件仍保存在工作区'); }
    if (uris.length !== checked.length) { throw new Error('系统返回的保存位置数量不匹配，未写入文件，请重试或改用 ZIP 打包'); }
    const outcome = new LumiBatchOutcome();
    for (let index = 0; index < checked.length; index++) {
      try {
        const target = await fs.open(uris[index], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try { await fs.copyFile(checked[index].path, target.fd); } finally { await fs.close(target); }
        outcome.succeeded.push(names[index]);
      } catch (error) { outcome.failed.push({ name: names[index], reason: (error as Error).message || '保存失败' }); }
    }
    if (outcome.failed.length) { throw new Error(batchOutcomeLabel(outcome)); }
  }

  static async archive(ctx: common.UIAbilityContext, files: WorkspaceFile[], name: string): Promise<WorkspaceFile> {
    const checked = await BatchFileService.checked(ctx, files);
    const names = batchFileNames(checked);
    const temporary = ctx.cacheDir + '/lumi_archive_' + Date.now().toString() + '_' + (++BatchFileService.sequence).toString();
    const outputName = FileService.cleanName((name.trim() || '文件合集').replace(/\.zip$/i, '')).slice(0, 110) + '.zip';
    const output = FileService.outputPath(ctx, outputName);
    fs.mkdirSync(temporary);
    let registered = false;
    try {
      for (let index = 0; index < checked.length; index++) { await fs.copyFile(checked[index].path, temporary + '/' + names[index]); }
      await zlib.compressFile(temporary, output, { level: zlib.CompressLevel.COMPRESS_LEVEL_BEST_SPEED, keepTopLevelFolder: false });
      const result = await FileService.register(ctx, output, outputName);
      registered = true;
      result.role = 'final'; result.sourcePaths = checked.map((file: WorkspaceFile): string => file.path);
      await FileService.updateDetails(ctx, result);
      return result;
    } finally {
      if (!registered && fs.accessSync(output)) { try { await fs.unlink(output); } catch (_) {} }
      if (fs.accessSync(temporary)) { try { await fs.rmdir(temporary); } catch (_) {} }
    }
  }

  static async organize(ctx: common.UIAbilityContext, files: WorkspaceFile[], kind: string, tags: string[] = [], collectionId: string = ''): Promise<LumiBatchOutcome> {
    if (!files.length || files.length > BatchFileService.MAX_FILES) { throw new Error('请选择 1–100 个文件'); }
    const outcome = new LumiBatchOutcome();
    for (const selected of files) {
      try {
        const current = (await FileService.list(ctx, true)).find((file: WorkspaceFile): boolean => file.path === selected.path);
        if (!current) { throw new Error('文件已移除'); }
        if (kind === 'trash') { await FileService.setTrash(ctx, current, true); }
        else if (kind === 'restore') { await FileService.setTrash(ctx, current, false); }
        else if (kind === 'tags' || kind === 'collection') {
          if (current.trashedAt) { throw new Error('请先恢复文件'); }
          if (kind === 'tags') {
            const merged = (current.tags || []).concat(tags).map((tag: string): string => tag.trim().slice(0, 24))
              .filter((tag: string, index: number, all: string[]): boolean => !!tag && all.indexOf(tag) === index);
            if (merged.length > 10) { throw new Error('添加后超过每个文件 10 个标签的上限，请先整理现有标签'); }
            current.tags = merged;
          }
          else { current.collectionId = collectionId; }
          await FileService.updateDetails(ctx, current);
        } else { throw new Error('不支持的批量操作'); }
        outcome.succeeded.push(current.path);
      } catch (error) { outcome.failed.push({ name: selected.name, reason: (error as Error).message || '操作未完成' }); }
    }
    return outcome;
  }
}
