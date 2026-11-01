export class LumiZipEntry {
  name: string = '';
  size: number = 0;
  crc: number = 0;
  offset: number = 0;
  compressed: number = 0;
  method: number = 0;
}
export class LumiXlsxSheet {
  name: string = '';
  csv: string = '';
}
export function safeZipEntries(bytes: Uint8Array): LumiZipEntry[] {
  const view = new DataView(bytes.buffer as ArrayBuffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length < 22) { throw new Error('Excel 文件不完整'); }
  let footer = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
    if (view.getUint32(i, true) === 0x06054b50 && i + 22 + view.getUint16(i + 20, true) === bytes.length) { footer = i; break; }
  }
  if (footer < 0 || view.getUint16(footer + 4, true) !== 0 || view.getUint16(footer + 6, true) !== 0) { throw new Error('不支持分卷、加密或损坏的 Excel 文件'); }
  const count = view.getUint16(footer + 10, true); const start = view.getUint32(footer + 16, true);
  if (count > 2000 || count !== view.getUint16(footer + 8, true) || start + view.getUint32(footer + 12, true) !== footer) { throw new Error('Excel 文件目录无效或过大'); }
  const results: LumiZipEntry[] = []; const names = new Set<string>(); let offset = start; let total = 0;
  for (let index = 0; index < count; index++) {
    if (offset + 46 > footer || view.getUint32(offset, true) !== 0x02014b50) { throw new Error('Excel 文件目录损坏'); }
    const flags = view.getUint16(offset + 8, true); const method = view.getUint16(offset + 10, true);
    const length = view.getUint16(offset + 28, true); const local = view.getUint32(offset + 42, true);
    const end = offset + 46 + length + view.getUint16(offset + 30, true) + view.getUint16(offset + 32, true);
    if (end > footer || flags & 1 || ![0, 8].includes(method) || local + 30 > start) { throw new Error('Excel 压缩结构不支持'); }
    // ZIP entry paths in an XLSX package are ASCII; reject ambiguous Unicode paths before native extraction.
    if (length > 240) { throw new Error('Excel 内部路径过长'); }
    const nameBytes = bytes.slice(offset + 46, offset + 46 + length);
    if (nameBytes.some((part: number) => part < 32 || part > 126)) { throw new Error('Excel 内部文件名不支持'); }
    const name = String.fromCharCode(...nameBytes);
    const segments = name.replace(/\/$/, '').split('/');
    if (!name || name.length > 240 || name.startsWith('/') || name.includes('\\') || name.includes(':') ||
      segments.some((part: string) => !part || part === '.' || part === '..') || names.has(name) ||
      ((view.getUint32(offset + 38, true) >>> 16) & 0xf000) === 0xa000) { throw new Error('Excel 包含不安全的内部路径'); }
    if (view.getUint32(local, true) !== 0x04034b50 || view.getUint16(local + 8, true) !== method || view.getUint16(local + 6, true) !== flags) { throw new Error('Excel 文件头不匹配'); }
    const localNameLength = view.getUint16(local + 26, true); const dataStart = local + 30 + localNameLength + view.getUint16(local + 28, true);
    const compressed = view.getUint32(offset + 20, true); const size = view.getUint32(offset + 24, true);
    if (localNameLength !== length || local + 30 + length > start || dataStart + compressed > start || size > 12 * 1024 * 1024 ||
      size === 0xffffffff || String.fromCharCode(...bytes.slice(local + 30, local + 30 + length)) !== name) { throw new Error('Excel 包大小或文件头无效'); }
    total += size; if (total > 32 * 1024 * 1024) { throw new Error('Excel 解压后上限为 32 MB'); }
    names.add(name); results.push({ name: name, size: size, crc: view.getUint32(offset + 16, true), offset: dataStart, compressed: compressed, method: method }); offset = end;
  }
  if (offset !== footer) { throw new Error('Excel 目录长度不一致'); }
  return results;
}
export function xlsxXmlText(text: string): string {
  if (/<!DOCTYPE|<!ENTITY/i.test(text)) { throw new Error('不支持含外部实体的 Excel XML'); }
  return text.replace(/<[^>]*>/g, '').replace(/&#x([0-9a-f]+);|&#([0-9]+);|&(amp|lt|gt|quot|apos);/gi,
    (match: string, hex: string, decimal: string, named: string): string => {
      if (hex || decimal) { const code = parseInt(hex || decimal, hex ? 16 : 10); return code >= 0 && code <= 0x10ffff ? String.fromCodePoint(code) : ''; }
      if (named === 'amp') { return '&'; } if (named === 'lt') { return '<'; } if (named === 'gt') { return '>'; }
      return named === 'quot' ? '"' : named === 'apos' ? "'" : match;
    });
}
export function xlsxAttribute(tag: string, name: string): string {
  const match = new RegExp('(?:^|\\s)' + name + '=["\']([^"\']*)["\']').exec(tag);
  return match ? xlsxXmlText(match[1]) : '';
}
export function xlsxSharedStrings(xml: string): string[] {
  if (/<!DOCTYPE|<!ENTITY/i.test(xml)) { throw new Error('Excel XML 无效'); }
  const results: string[] = []; const pattern = /<(?:\w+:)?si(?:\s[^>]*)?>([\s\S]*?)<\/(?:\w+:)?si>/g;
  let match = pattern.exec(xml);
  while (match) {
    const texts = match[1].match(/<(?:\w+:)?t(?:\s[^>]*)?>[\s\S]*?<\/(?:\w+:)?t>/g) || [];
    results.push(texts.map((part: string) => xlsxXmlText(part)).join('')); match = pattern.exec(xml);
  }
  return results;
}
export function xlsxDateStyles(xml: string): boolean[] {
  const formats = new Map<string, string>();
  const formatPattern = /<(?:\w+:)?numFmt\s([^>]+)\/?\s*>/g; let format = formatPattern.exec(xml);
  while (format) { formats.set(xlsxAttribute(format[1], 'numFmtId'), xlsxAttribute(format[1], 'formatCode')); format = formatPattern.exec(xml); }
  const section = /<(?:\w+:)?cellXfs[^>]*>([\s\S]*?)<\/(?:\w+:)?cellXfs>/.exec(xml);
  if (!section) { return []; }
  const results: boolean[] = []; const pattern = /<(?:\w+:)?xf\s([^>]+)>/g; let match = pattern.exec(section[1]);
  while (match) {
    const id = xlsxAttribute(match[1], 'numFmtId'); const custom = (formats.get(id) || '').replace(/"[^"]*"|\[[^\]]*\]|\\./g, '');
    results.push((Number(id) >= 14 && Number(id) <= 22) || (Number(id) >= 45 && Number(id) <= 47) || /[yd]/i.test(custom));
    match = pattern.exec(section[1]);
  }
  return results;
}
function xlsxDate(serial: number, date1904: boolean): string {
  if (!Number.isFinite(serial) || serial < 0 || serial > 2958465) { return serial.toString(); }
  const epoch = date1904 ? Date.UTC(1904, 0, 1) : serial < 60 ? Date.UTC(1899, 11, 31) : Date.UTC(1899, 11, 30);
  const date = new Date(epoch + Math.round(serial * 86400000));
  const iso = date.toISOString(); return iso.substring(0, 10) + (serial % 1 ? ' ' + iso.substring(11, 19) : '');
}
export function xlsxSheetCsv(xml: string, shared: string[], dateStyles: boolean[] = [], date1904: boolean = false): string {
  if (/<!DOCTYPE|<!ENTITY/i.test(xml)) { throw new Error('Excel XML 无效'); }
  const rows: Map<number, Map<number, string>> = new Map<number, Map<number, string>>(); let maxColumn = 0; let minRow = 20002; let maxRow = 0;
  const pattern = /<(?:\w+:)?c\s([^>]*[^/])>([\s\S]*?)<\/(?:\w+:)?c>/g; let match = pattern.exec(xml);
  while (match) {
    const reference = /^([A-Z]+)([1-9]\d*)$/.exec(xlsxAttribute(match[1], 'r'));
    const type = xlsxAttribute(match[1], 't'); const raw = /<(?:\w+:)?v(?:\s[^>]*)?>([\s\S]*?)<\/(?:\w+:)?v>/.exec(match[2]);
    let text = type === 'inlineStr' ? xlsxSharedStrings('<si>' + match[2] + '</si>')[0] || '' : raw ? xlsxXmlText(raw[1]) : '';
    if (type === 's' && raw) { const index = Number(text); if (!Number.isInteger(index) || index < 0 || index >= shared.length) { throw new Error('Excel 共享文本索引无效'); } text = shared[index]; }
    if (type === 'b') { text = text === '1' ? 'true' : 'false'; }
    if (text && (!type || type === 'n') && dateStyles[Number(xlsxAttribute(match[1], 's'))]) { text = xlsxDate(Number(text), date1904); }
    if (text) {
      if (!reference) { throw new Error('Excel 单元格坐标无效'); }
      let column = 0; for (let index = 0; index < reference[1].length; index++) { column = column * 26 + reference[1].charCodeAt(index) - 64; }
      const row = Number(reference[2]);
      if (column > 100 || row > 20001) { throw new Error('Excel 最多支持 20,000 行数据和 100 列'); }
      let cells = rows.get(row); if (!cells) { cells = new Map<number, string>(); rows.set(row, cells); }
      if (cells.has(column)) { throw new Error('Excel 含重复单元格'); } cells.set(column, text);
      maxColumn = Math.max(maxColumn, column); minRow = Math.min(minRow, row); maxRow = Math.max(maxRow, row);
    }
    match = pattern.exec(xml);
  }
  if (!rows.size) { return ''; }
  const output: string[] = [];
  for (let row = minRow; row <= maxRow; row++) {
    const cells = rows.get(row); const values: string[] = [];
    for (let column = 1; column <= maxColumn; column++) {
      const text = cells?.get(column) || ''; values.push('"' + text.replace(/"/g, '""') + '"');
    }
    output.push(values.join(','));
  }
  return output.join('\r\n');
}
