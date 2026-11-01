export interface DataTable { headers: string[]; rows: string[][]; }
export interface NumericSummary { count: number; empty: number; sum: number; mean: number; min: number; max: number; }
export interface GroupSummary { label: string; count: number; sum: number; }
type FlatValue = string | number | boolean | null;

/** RFC 4180 style parser: escaped quotes, quoted commas/newlines, UTF-8 BOM. */
export class DataEngine {
  static readonly MAX_ROWS: number = 20000;
  static parseCSV(input: string): DataTable {
    const text = input.replace(/^\uFEFF/, '');
    if (text.length > 4 * 1024 * 1024) { throw new Error('CSV 文本上限为 4 MB'); }
    const records: string[][] = [];
    let row: string[] = [];
    let cell: string = '';
    let quoted: boolean = false;
    let closed: boolean = false;
    for (let i = 0; i < text.length; i++) {
      const char = text[i];
      if (quoted) {
        if (char === '"') {
          if (text[i + 1] === '"') { cell += '"'; i++; } else { quoted = false; closed = true; }
        } else { cell += char; }
      } else if (char === ',' || char === '\n' || char === '\r') {
        row.push(cell); cell = ''; closed = false;
        if (row.length > 100) { throw new Error('最多支持 100 列'); }
        if (char !== ',') {
          records.push(row); row = [];
          if (char === '\r' && text[i + 1] === '\n') { i++; }
          if (records.length > DataEngine.MAX_ROWS + 1) { throw new Error('最多支持 20,000 行，请先拆分文件'); }
        }
      } else if (char === '"') {
        if (cell.length > 0 || closed) { throw new Error('CSV 引号位置不正确'); }
        quoted = true;
      } else {
        if (closed) { throw new Error('CSV 闭合引号后应为逗号或换行'); }
        cell += char;
      }
    }
    if (quoted) { throw new Error('CSV 含未闭合的引号'); }
    if (cell.length > 0 || row.length > 0 || closed) { row.push(cell); records.push(row); }
    if (records.length === 0) { throw new Error('请先导入或输入 CSV'); }
    if (records.length > DataEngine.MAX_ROWS + 1) { throw new Error('最多支持 20,000 行，请先拆分文件'); }
    const original = records.shift() as string[];
    if (original.length > 100) { throw new Error('最多支持 100 列'); }
    const headers: string[] = [];
    original.forEach((value: string, index: number) => {
      const base = value.trim() || ('字段' + (index + 1).toString());
      let unique = base; let suffix = 2;
      while (headers.includes(unique)) { unique = base + '_' + suffix.toString(); suffix++; }
      headers.push(unique);
    });
    const rows = records.map((value: string[], index: number) => {
      if (value.length > headers.length) { throw new Error('第 ' + (index + 2).toString() + ' 行列数超过表头'); }
      const next = value.slice();
      while (next.length < headers.length) { next.push(''); }
      return next;
    });
    return { headers: headers, rows: rows };
  }

  static csv(table: DataTable): string {
    const quote = (text: string): string => /[",\r\n]/.test(text) ? '"' + text.replace(/"/g, '""') + '"' : text;
    return [table.headers].concat(table.rows).map((row: string[]) => row.map(quote).join(',')).join('\r\n');
  }

  static json(table: DataTable): string {
    if (table.rows.length === 0) { return '[]'; }
    return '[\n' + table.rows.map((row: string[]) => '  {\n' + table.headers.map((header: string, index: number) =>
      '    ' + JSON.stringify(header) + ': ' + JSON.stringify(row[index] || '')).join(',\n') + '\n  }').join(',\n') + '\n]';
  }

  static fromJSON(text: string): DataTable {
    if (text.length > 4 * 1024 * 1024) { throw new Error('JSON 文本上限为 4 MB'); }
    const input = JSON.parse(text) as Record<string, FlatValue>[];
    if (!Array.isArray(input) || input.length === 0 || input.length > DataEngine.MAX_ROWS) {
      throw new Error('JSON 必须为 1 至 20,000 条扁平对象组成的数组');
    }
    const headers: string[] = [];
    input.forEach((record: Record<string, FlatValue>) => {
      if (record === null || typeof record !== 'object' || Array.isArray(record)) { throw new Error('每一条记录必须是对象'); }
      Object.keys(record).forEach((key: string) => { if (!headers.includes(key)) { headers.push(key); } });
    });
    if (headers.length === 0 || headers.length > 100) { throw new Error('JSON 对象需要 1 至 100 个字段'); }
    const rows = input.map((record: Record<string, FlatValue>) => headers.map((key: string) => {
      const value = record[key];
      if (value === null || value === undefined) { return ''; }
      if (typeof value === 'object') { throw new Error('不支持嵌套对象或数组，请先将 JSON 展平'); }
      return String(value);
    }));
    return { headers: headers, rows: rows };
  }

  static summary(table: DataTable, column: number): NumericSummary {
    const values = table.rows.map((row: string[]) => row[column].trim()).filter((text: string) => text !== '' && Number.isFinite(Number(text))).map((text: string) => Number(text));
    const sum = values.reduce((total: number, value: number) => total + value, 0);
    let min = values.length > 0 ? values[0] : 0;
    let max = min;
    values.forEach((value: number) => { min = Math.min(min, value); max = Math.max(max, value); });
    return { count: values.length, empty: table.rows.filter((row: string[]) => row[column].trim() === '').length,
      sum: sum, mean: values.length > 0 ? sum / values.length : 0, min: min, max: max };
  }

  static groups(table: DataTable, column: number, numeric: number): GroupSummary[] {
    const groups = new Map<string, GroupSummary>();
    table.rows.forEach((row: string[]) => {
      const key = row[column];
      let group = groups.get(key);
      if (!group) { group = { label: key, count: 0, sum: 0 }; groups.set(key, group); }
      group.count++;
      if (row[numeric].trim() !== '' && Number.isFinite(Number(row[numeric]))) { group.sum += Number(row[numeric]); }
    });
    return Array.from(groups.values());
  }
}
