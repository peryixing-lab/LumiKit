import { fileIo as fs } from '@kit.CoreFileKit';
import { readXmlEntry } from './XlsxArchive';
import { taskpool } from '@kit.ArkTS';
import { LumiZipEntry, LumiXlsxSheet, safeZipEntries, xlsxAttribute, xlsxDateStyles, xlsxSharedStrings, xlsxSheetCsv } from './XlsxParser';

@Concurrent
export async function readXlsx(path: string): Promise<LumiXlsxSheet[]> {
  if (fs.statSync(path).size > 20 * 1024 * 1024) { throw new Error('Excel 文件请控制在 20 MB 以内'); }
  const file = await fs.open(path, fs.OpenMode.READ_ONLY);
  const bytes = new Uint8Array(fs.statSync(path).size);
  try {
    let position = 0;
    while (position < bytes.length) {
      const buffer = new ArrayBuffer(bytes.length - position); const count = await fs.read(file.fd, buffer);
      if (count <= 0) { throw new Error('Excel 文件不完整'); } bytes.set(new Uint8Array(buffer, 0, count), position); position += count;
    }
  } finally { await fs.close(file); }
  const entries = safeZipEntries(bytes);
  const workbook = await readXmlEntry(bytes, entries, 'xl/workbook.xml');
  const rels = await readXmlEntry(bytes, entries, 'xl/_rels/workbook.xml.rels');
  if (/<!DOCTYPE|<!ENTITY/i.test(workbook + rels)) { throw new Error('Excel 结构无效'); }
  const shared = xlsxSharedStrings(await readXmlEntry(bytes, entries, 'xl/sharedStrings.xml', true));
  const styles = xlsxDateStyles(await readXmlEntry(bytes, entries, 'xl/styles.xml', true));
    const targets = new Map<string, string>(); const relPattern = /<(?:\w+:)?Relationship\s([^>]+)>/g; let relation = relPattern.exec(rels);
    while (relation) {
      if (xlsxAttribute(relation[1], 'TargetMode') !== 'External') { targets.set(xlsxAttribute(relation[1], 'Id'), xlsxAttribute(relation[1], 'Target')); }
      relation = relPattern.exec(rels);
    }
    const results: LumiXlsxSheet[] = []; const sheetPattern = /<(?:\w+:)?sheet\s([^>]+)>/g; let sheet = sheetPattern.exec(workbook);
    const date1904 = /date1904=["'](?:1|true)["']/.test(workbook);
    while (sheet) {
      const name = xlsxAttribute(sheet[1], 'name'); const target = targets.get(xlsxAttribute(sheet[1], 'r:id')) || '';
      const relative = target.startsWith('/xl/') ? target.substring(1) : 'xl/' + target;
      if (!/^xl\/worksheets\/[A-Za-z0-9_.-]+\.xml$/.test(relative) || !entries.some((entry) => entry.name === relative)) { throw new Error('工作表路径无效'); }
      const csv = xlsxSheetCsv(await readXmlEntry(bytes, entries, relative), shared, styles, date1904);
      results.push({ name: name, csv: csv }); if (results.length > 30) { throw new Error('工作簿最多支持 30 张工作表'); }
      sheet = sheetPattern.exec(workbook);
    }
    if (!results.length) { throw new Error('未找到工作表'); } return results;
}
