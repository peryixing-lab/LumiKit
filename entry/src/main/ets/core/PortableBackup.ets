import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { FileService, WorkspaceFile } from './FileService';
import { LumiBackup, BackupDocument, StorageService } from './StorageService';
import { InventoryItem, LocalAttachment } from '../features/inventory/InventoryModels';
import { FormResponse, FieldAnswer } from '../features/forms/FormModels';
import { LumiFormDraft } from '../features/forms/FormDrafts';
import { LumiCollection, validCollection } from '../features/workbench/WorkbenchModels';
import { validateBackupDocument } from './BackupValidation';
import { LumiMaterialPack, LumiMaterialItem } from '../features/materials/MaterialPackModels';

export class LumiBackupEntry {
  source: string = '';
  name: string = '';
  size: number = 0;
  crc: number = 0;
  details?: WorkspaceFile;
}
export class LumiPortableManifest {
  format: string = 'LumiKit.complete';
  version: number = 2;
  createdAt: number = Date.now();
  metadata: string = '';
  metadataCrc: number = 0;
  files: LumiBackupEntry[] = [];
}
export function lumiCrc(bytes: Uint8Array, previous: number = 0): number {
  const table = new Uint32Array(256);
  for (let index = 0; index < 256; index++) {
    let part = index;
    for (let bit = 0; bit < 8; bit++) { part = (part >>> 1) ^ ((part & 1) ? 0xedb88320 : 0); }
    table[index] = part >>> 0;
  }
  let crc = previous ^ 0xffffffff;
  for (let i = 0; i < bytes.length; i++) { crc = (crc >>> 8) ^ table[(crc ^ bytes[i]) & 255]; }
  return (crc ^ 0xffffffff) >>> 0;
}
export function validatePortableManifest(manifest: LumiPortableManifest, payloadSize: number): void {
  if (!manifest || manifest.format !== 'LumiKit.complete' || manifest.version !== 2 ||
    typeof manifest.metadata !== 'string' || !Array.isArray(manifest.files) || manifest.files.length > 10000) {
    throw new Error('这不是支持的完整备份');
  }
  if (lumiCrc(new util.TextEncoder().encodeInto(manifest.metadata)) !== manifest.metadataCrc) { throw new Error('备份资料校验失败'); }
  const metadata = JSON.parse(manifest.metadata) as LumiBackup;
  if (!metadata || metadata.format !== 'LumiKit.metadata' || metadata.version !== 1 ||
    !Array.isArray(metadata.documents) || !Array.isArray(metadata.history)) { throw new Error('备份资料无效'); }
  for (const document of metadata.documents) {
    if (!document || typeof document.key !== 'string' || typeof document.value !== 'string' ||
      !validateBackupDocument(document.key, document.value)) { throw new Error('备份资料校验失败'); }
  }
  const sources = new Set<string>();
  let total = 0;
  for (const entry of manifest.files) {
    if (!entry || typeof entry.source !== 'string' || !entry.source || sources.has(entry.source) ||
      typeof entry.name !== 'string' || !entry.name || !Number.isSafeInteger(entry.size) || entry.size < 0 ||
      entry.size > 1024 * 1024 * 1024 || !Number.isInteger(entry.crc) || entry.crc < 0 || entry.crc > 0xffffffff) {
      throw new Error('备份文件清单无效');
    }
    if (entry.details) {
      const detail = entry.details;
      if ((detail.trashedAt !== undefined && (!Number.isFinite(detail.trashedAt) || detail.trashedAt < 0)) ||
        (detail.collectionId !== undefined && typeof detail.collectionId !== 'string') ||
        (detail.role !== undefined && !['', 'source', 'intermediate', 'final'].includes(detail.role)) ||
        (detail.pageCount !== undefined && (!Number.isInteger(detail.pageCount) || detail.pageCount < 0)) ||
        (detail.tags !== undefined && (!Array.isArray(detail.tags) || detail.tags.length > 10 || !detail.tags.every((tag: string) => typeof tag === 'string' && tag.length <= 24))) ||
        (detail.sourcePaths !== undefined && (!Array.isArray(detail.sourcePaths) || detail.sourcePaths.length > 200 || !detail.sourcePaths.every((path: string) => typeof path === 'string')))) {
        throw new Error('备份文件关联信息无效');
      }
    }
    sources.add(entry.source); total += entry.size;
  }
  if (total !== payloadSize || total > 1024 * 1024 * 1024) { throw new Error('备份长度不符或超过 1 GB'); }
  for (const document of metadata.documents) {
    if (document.key === 'material.packs') {
      for (const pack of JSON.parse(document.value) as LumiMaterialPack[]) {
        if (pack.items.some((item: LumiMaterialItem): boolean => !!item.path && !sources.has(item.path))) { throw new Error('材料包包含未打包的文件，请重新关联后备份'); }
      }
    }
  }
}

/** A bounded streaming container: magic + manifest length + UTF-8 manifest + file bytes. */
export class PortableBackup {
  private static readonly MAGIC: string = 'LUMIBAK2\n';
  private static async readExactly(fd: number, length: number): Promise<ArrayBuffer> {
    const result = new Uint8Array(length);
    let position = 0;
    while (position < length) {
      const buffer = new ArrayBuffer(length - position);
      const count = await fs.read(fd, buffer);
      if (count <= 0) { throw new Error('备份不完整，请重新选择'); }
      result.set(new Uint8Array(buffer, 0, count), position); position += count;
    }
    return result.buffer;
  }
  private static async writeAll(fd: number, data: ArrayBuffer): Promise<void> {
    let position = 0;
    while (position < data.byteLength) {
      const count = await fs.write(fd, data.slice(position));
      if (count <= 0) { throw new Error('备份写入失败，可能存储空间不足'); }
      position += count;
    }
  }
  private static async checksum(path: string): Promise<number> {
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    let crc = 0;
    try {
      const buffer = new ArrayBuffer(256 * 1024);
      let count = await fs.read(file.fd, buffer);
      while (count > 0) { crc = lumiCrc(new Uint8Array(buffer, 0, count), crc); count = await fs.read(file.fd, buffer); }
    } finally { await fs.close(file); }
    return crc;
  }
  static async create(ctx: common.UIAbilityContext, progress: (message: string) => void): Promise<WorkspaceFile> {
    const manifest = new LumiPortableManifest();
    manifest.metadata = await StorageService.exportBackup();
    manifest.metadataCrc = lumiCrc(new util.TextEncoder().encodeInto(manifest.metadata));
    const files = (await FileService.list(ctx, true)).filter((entry: WorkspaceFile) => !entry.name.toLowerCase().endsWith('.lumibak'));
    const metadata = JSON.parse(manifest.metadata) as LumiBackup;
    const attachments: LocalAttachment[] = [];
    const materialPaths: string[] = [];
    for (const document of metadata.documents) {
      if (document.key === 'inventory.items') { for (const item of JSON.parse(document.value) as InventoryItem[]) { attachments.push(...item.attachments); } }
      if (document.key === 'forms.responses') { for (const response of JSON.parse(document.value) as FormResponse[]) { for (const answer of response.answers) { attachments.push(...answer.attachments); } } }
      if (document.key === 'forms.autodraft') { const draft = JSON.parse(document.value) as LumiFormDraft; if (draft) { for (const answer of draft.answers) { attachments.push(...answer.attachments); } } }
      if (document.key === 'material.packs') { for (const pack of JSON.parse(document.value) as LumiMaterialPack[]) { for (const item of pack.items) { if (item.path) { materialPaths.push(item.path); } } } }
    }
    const missing = attachments.filter((attachment: LocalAttachment) => !files.some((file: WorkspaceFile) => file.path === attachment.path));
    if (missing.length) { throw new Error('有 ' + missing.length.toString() + ' 个附件缺失，请重新导入并关联后再完整备份'); }
    if (materialPaths.some((path: string): boolean => !files.some((file: WorkspaceFile): boolean => file.path === path))) {
      throw new Error('材料包中有文件缺失，请重新关联或解除关联后再完整备份');
    }
    const total = files.reduce((sum: number, entry: WorkspaceFile) => sum + entry.size, 0);
    if (total > 1024 * 1024 * 1024) { throw new Error('完整备份上限为 1 GB，请先导出并清理较大的处理结果'); }
    for (let i = 0; i < files.length; i++) {
      progress('检查文件 ' + (i + 1).toString() + '/' + files.length.toString());
      const entry = new LumiBackupEntry();
      entry.source = files[i].path; entry.name = files[i].name; entry.size = files[i].size;
      entry.details = files[i];
      entry.crc = await PortableBackup.checksum(files[i].path); manifest.files.push(entry);
    }
    const encoded = new util.TextEncoder().encodeInto(JSON.stringify(manifest));
    if (encoded.length > 8 * 1024 * 1024) { throw new Error('备份清单过大'); }
    const header = new Uint8Array(13);
    header.set(new util.TextEncoder().encodeInto(PortableBackup.MAGIC));
    new DataView(header.buffer).setUint32(9, encoded.length, true);
    const name = '集萤_完整备份_' + Date.now().toString() + '.lumibak';
    const path = FileService.outputPath(ctx, name);
    const target = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    let complete = false;
    try {
      await PortableBackup.writeAll(target.fd, header.buffer as ArrayBuffer);
      await PortableBackup.writeAll(target.fd, encoded.buffer as ArrayBuffer);
      for (let i = 0; i < files.length; i++) {
        progress('备份文件 ' + (i + 1).toString() + '/' + files.length.toString());
        const source = await fs.open(files[i].path, fs.OpenMode.READ_ONLY);
        let crc = 0; let copied = 0;
        try {
          const buffer = new ArrayBuffer(256 * 1024);
          let count = await fs.read(source.fd, buffer);
          while (count > 0) {
            copied += count; crc = lumiCrc(new Uint8Array(buffer, 0, count), crc);
            await PortableBackup.writeAll(target.fd, buffer.slice(0, count)); count = await fs.read(source.fd, buffer);
          }
        } finally { await fs.close(source); }
        if (copied !== files[i].size || crc !== manifest.files[i].crc) { throw new Error('备份期间文件发生变化，请重试'); }
      }
      complete = true;
    } finally { await fs.close(target); if (!complete && fs.accessSync(path)) { await fs.unlink(path); } }
    return FileService.register(ctx, path, name);
  }
  static async inspect(ctx: common.UIAbilityContext, path: string): Promise<LumiPortableManifest> {
    FileService.assertOwned(ctx, path);
    const source = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const header = await PortableBackup.readExactly(source.fd, 13);
      if (new util.TextDecoder().decodeToString(new Uint8Array(header, 0, 9)) !== PortableBackup.MAGIC) { throw new Error('备份格式不支持'); }
      const length = new DataView(header).getUint32(9, true);
      if (length < 2 || length > 8 * 1024 * 1024) { throw new Error('备份清单长度无效'); }
      const bytes = await PortableBackup.readExactly(source.fd, length);
      const manifest = JSON.parse(new util.TextDecoder().decodeToString(new Uint8Array(bytes))) as LumiPortableManifest;
      validatePortableManifest(manifest, fs.statSync(path).size - 13 - length);
      return manifest;
    } finally { await fs.close(source); }
  }
  static async restore(ctx: common.UIAbilityContext, path: string, progress: (message: string) => void): Promise<void> {
    const manifest = await PortableBackup.inspect(ctx, path);
    const source = await fs.open(path, fs.OpenMode.READ_ONLY);
    const created: string[] = [];
    let committed = false;
    try {
      const header = await PortableBackup.readExactly(source.fd, 13);
      await PortableBackup.readExactly(source.fd, new DataView(header).getUint32(9, true));
      let metadata = manifest.metadata;
      const restored: WorkspaceFile[] = [];
      for (let i = 0; i < manifest.files.length; i++) {
        const entry = manifest.files[i];
        progress('恢复文件 ' + (i + 1).toString() + '/' + manifest.files.length.toString());
        const output = FileService.outputPath(ctx, entry.name); created.push(output);
        const target = await fs.open(output, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        let remaining = entry.size; let crc = 0;
        try {
          while (remaining > 0) {
            const data = await PortableBackup.readExactly(source.fd, Math.min(256 * 1024, remaining));
            crc = lumiCrc(new Uint8Array(data), crc); await PortableBackup.writeAll(target.fd, data); remaining -= data.byteLength;
          }
        } finally { await fs.close(target); }
        if (crc !== entry.crc) { throw new Error('文件校验失败：' + entry.name + '。原有资料未被替换'); }
        // Replace complete JSON string tokens only, so escaped paths and prefix collisions remain safe.
        const backup = JSON.parse(metadata) as LumiBackup;
        for (const document of backup.documents) { document.value = document.value.split(JSON.stringify(entry.source)).join(JSON.stringify(output)); }
        for (const record of backup.history) { if (record.outputPath === entry.source) { record.outputPath = output; } }
        metadata = JSON.stringify(backup);
        restored.push({ id: output.substring(output.lastIndexOf('/') + 1), name: entry.name, path: output, size: entry.size,
          mime: FileService.mime(entry.name), createdAt: manifest.createdAt,
          trashedAt: entry.details?.trashedAt || 0, collectionId: entry.details?.collectionId || '',
          tags: entry.details?.tags || [], role: entry.details?.role || '', pageCount: entry.details?.pageCount || 0,
          sourcePaths: entry.details?.sourcePaths || [] });
      }
      for (const restoredFile of restored) {
        restoredFile.sourcePaths = (restoredFile.sourcePaths || []).map((sourcePath: string) => {
          const index = manifest.files.findIndex((entry: LumiBackupEntry) => entry.source === sourcePath);
          return index >= 0 ? restored[index].path : '';
        }).filter((sourcePath: string) => !!sourcePath);
      }
      const finalBackup = JSON.parse(metadata) as LumiBackup;
      // Existing workspace files remain after restore, so preserve their collection labels too.
      const collectionDocument = finalBackup.documents.find((document: BackupDocument) => document.key === 'workspace.collections');
      if (collectionDocument) {
        const incoming = JSON.parse(collectionDocument.value) as LumiCollection[];
        const existing = JSON.parse(await StorageService.getValue('workspace.collections', '[]')) as LumiCollection[];
        if (!Array.isArray(existing) || !existing.every(validCollection)) { throw new Error('当前资料集合无法读取，未覆盖已有资料'); }
        collectionDocument.value = JSON.stringify(incoming.concat(existing.filter((entry: LumiCollection) => !incoming.some((item: LumiCollection) => item.id === entry.id))));
      }
      for (const record of finalBackup.history) { if (record.outputPath && !restored.some((file: WorkspaceFile) => file.path === record.outputPath)) { record.outputPath = ''; } }
      metadata = JSON.stringify(finalBackup);
      const catalog = restored.concat(await FileService.list(ctx, true));
      await StorageService.restoreBackup(metadata, [{ key: 'workspace', value: JSON.stringify(catalog) }]);
      committed = true;
    } finally {
      await fs.close(source);
      if (!committed) { for (const output of created) { if (fs.accessSync(output)) { await fs.unlink(output); } } }
    }
  }
}
