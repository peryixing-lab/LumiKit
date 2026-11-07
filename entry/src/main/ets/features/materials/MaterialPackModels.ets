/** User-authored requirements only; no institution-specific submission rules. */
export class LumiMaterialItem {
  id: string = '';
  name: string = '';
  format: string = 'any';
  maxMB: string = '';
  path: string = '';
}

export class LumiMaterialPack {
  id: string = '';
  name: string = '';
  items: LumiMaterialItem[] = [];
  createdAt: number = 0;
  updatedAt: number = 0;
}

export class LumiMaterialTemplate {
  id: string = '';
  name: string = '';
  items: LumiMaterialItem[] = [];
  createdAt: number = 0;
}

export const LUMI_MATERIAL_FORMATS: string[] = ['any', 'pdf', 'image', 'jpeg', 'png', 'webp', 'csv', 'xlsx', 'text'];
export const LUMI_MATERIAL_FORMAT_LABELS: string[] = ['不限格式', 'PDF', '图片', 'JPEG', 'PNG', 'WebP', 'CSV', 'Excel（XLSX）', '文本（TXT / Markdown）'];

export function validMaterialItem(item: LumiMaterialItem): boolean {
  return !!item && typeof item.id === 'string' && item.id.length > 0 && item.id.length <= 100 &&
    typeof item.name === 'string' && item.name.trim().length > 0 && item.name.length <= 80 &&
    typeof item.format === 'string' && LUMI_MATERIAL_FORMATS.includes(item.format) &&
    typeof item.maxMB === 'string' && item.maxMB.length <= 16 &&
    (!item.maxMB || (Number.isFinite(Number(item.maxMB)) && Number(item.maxMB) > 0 && Number(item.maxMB) <= 100)) &&
    typeof item.path === 'string' && item.path.length <= 2048;
}

function validMaterialItems(items: LumiMaterialItem[]): boolean {
  return Array.isArray(items) && items.length <= 20 && items.every(validMaterialItem) &&
    new Set(items.map((item: LumiMaterialItem): string => item.id)).size === items.length;
}

export function validMaterialPack(pack: LumiMaterialPack): boolean {
  return !!pack && typeof pack.id === 'string' && pack.id.length > 0 && pack.id.length <= 100 &&
    typeof pack.name === 'string' && pack.name.trim().length > 0 && pack.name.length <= 80 && validMaterialItems(pack.items) &&
    Number.isFinite(pack.createdAt) && pack.createdAt > 0 && Number.isFinite(pack.updatedAt) && pack.updatedAt > 0;
}

export function validMaterialTemplate(template: LumiMaterialTemplate): boolean {
  return !!template && typeof template.id === 'string' && template.id.length > 0 && template.id.length <= 100 &&
    typeof template.name === 'string' && template.name.trim().length > 0 && template.name.length <= 80 &&
    validMaterialItems(template.items) && template.items.length > 0 &&
    template.items.every((item: LumiMaterialItem): boolean => item.path === '') &&
    Number.isFinite(template.createdAt) && template.createdAt > 0;
}

export function materialFormatMatches(format: string, name: string): boolean {
  if (!LUMI_MATERIAL_FORMATS.includes(format)) { return false; }
  if (format === 'any') { return true; }
  const extension = name.toLowerCase().split('.').pop() || '';
  if (format === 'image') { return ['png', 'jpg', 'jpeg', 'webp', 'heic'].includes(extension); }
  if (format === 'jpeg') { return ['jpg', 'jpeg'].includes(extension); }
  if (format === 'text') { return ['txt', 'md', 'markdown'].includes(extension); }
  return extension === format;
}

/** Derive the status from the current file index, never persist a stale “ready” flag. */
export function materialItemStatus(item: LumiMaterialItem, fileName: string, fileSize: number): string {
  if (!item.path || !fileName || !Number.isFinite(fileSize) || fileSize < 0) { return '待添加'; }
  if (!materialFormatMatches(item.format, fileName)) { return '格式不符合'; }
  if (item.maxMB && fileSize > Number(item.maxMB) * 1024 * 1024) { return '超出大小'; }
  return '已准备';
}

export function materialTemplateFromPack(pack: LumiMaterialPack, id: string, name: string): LumiMaterialTemplate {
  const template = new LumiMaterialTemplate();
  template.id = id; template.name = name.trim(); template.createdAt = Date.now();
  template.items = pack.items.map((item: LumiMaterialItem): LumiMaterialItem => ({
    id: item.id, name: item.name, format: item.format, maxMB: item.maxMB, path: ''
  }));
  return template;
}
