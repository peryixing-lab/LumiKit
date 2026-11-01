/** Offline, platform-independent transformations. User content is never persisted here. */
export class ColorConversion {
  hex: string = '';
  rgb: string = '';
  hsl: string = '';
}

export class TimestampConversion {
  seconds: string = '';
  milliseconds: string = '';
  local: string = '';
  utc: string = '';
}

export class DiffLine {
  kind: string;
  text: string;
  oldLine: number;
  newLine: number;

  constructor(kind: string, text: string, oldLine: number, newLine: number) {
    this.kind = kind;
    this.text = text;
    this.oldLine = oldLine;
    this.newLine = newLine;
  }
}

export class MarkdownInline {
  text: string;
  kind: string;

  constructor(text: string, kind: string = 'text') {
    this.text = text;
    this.kind = kind;
  }
}

export class MarkdownBlock {
  kind: string;
  text: string;
  inlines: MarkdownInline[];

  constructor(kind: string, text: string) {
    this.kind = kind;
    this.text = text;
    this.inlines = markdownInlines(text);
  }
}

export function validateJson(input: string): void {
  if (input.length > 200000) {
    throw new Error('JSON 最多支持 200,000 个字符，请缩小内容后重试。');
  }
  if (input.trim().length === 0) {
    throw new Error('请先输入 JSON 内容。');
  }
  JSON.parse(input);
}

export function formatJson(input: string, compact: boolean = false): string {
  // Validate with the native parser, then format the original tokens. This preserves
  // large integer literals exactly instead of rounding them through Number.
  validateJson(input);
  let output: string = '';
  let inString: boolean = false;
  let escaped: boolean = false;
  let depth: number = 0;
  const source: string = input.trim();
  for (let index: number = 0; index < source.length; index++) {
    const char: string = source.charAt(index);
    if (inString) {
      output += char;
      if (escaped) {
        escaped = false;
      } else if (char === '\\') {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }
    if (char === '"') {
      inString = true;
      output += char;
    } else if (/\s/.test(char)) {
      continue;
    } else if (compact) {
      output += char;
    } else if (char === '{' || char === '[') {
      output += char;
      depth++;
      if (depth > 128) {
        throw new Error('JSON 嵌套层级超过 128 层，请简化后再格式化。');
      }
      let next: number = index + 1;
      while (next < source.length && /\s/.test(source.charAt(next))) {
        next++;
      }
      if (source.charAt(next) !== '}' && source.charAt(next) !== ']') {
        output += '\n' + '  '.repeat(depth);
      }
    } else if (char === '}' || char === ']') {
      depth--;
      let previous: number = index - 1;
      while (previous >= 0 && /\s/.test(source.charAt(previous))) {
        previous--;
      }
      if (source.charAt(previous) !== '{' && source.charAt(previous) !== '[') {
        output += '\n' + '  '.repeat(depth);
      }
      output += char;
    } else if (char === ',') {
      output += ',\n' + '  '.repeat(depth);
    } else if (char === ':') {
      output += ': ';
    } else {
      output += char;
    }
    if (output.length > 2000000) {
      throw new Error('格式化结果超过 2,000,000 个字符，请使用压缩或校验。');
    }
  }
  return output;
}

export function encodeBase64(input: string): string {
  const alphabet: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const encoded: string = encodeURIComponent(input);
  const bytes: number[] = [];
  for (let index: number = 0; index < encoded.length; index++) {
    if (encoded.charAt(index) === '%') {
      bytes.push(parseInt(encoded.substring(index + 1, index + 3), 16));
      index += 2;
    } else {
      bytes.push(encoded.charCodeAt(index));
    }
  }
  let output: string = '';
  for (let index: number = 0; index < bytes.length; index += 3) {
    const first: number = bytes[index];
    const second: number = index + 1 < bytes.length ? bytes[index + 1] : 0;
    const third: number = index + 2 < bytes.length ? bytes[index + 2] : 0;
    output += alphabet.charAt(first >> 2);
    output += alphabet.charAt(((first & 3) << 4) | (second >> 4));
    output += index + 1 < bytes.length ? alphabet.charAt(((second & 15) << 2) | (third >> 6)) : '=';
    output += index + 2 < bytes.length ? alphabet.charAt(third & 63) : '=';
  }
  return output;
}

export function decodeBase64(input: string): string {
  const source: string = input.replace(/\s/g, '');
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(source)) {
    throw new Error('Base64 格式不正确，请检查字符、长度和末尾的 = 补位。');
  }
  const alphabet: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let encoded: string = '';
  for (let index: number = 0; index < source.length; index += 4) {
    const first: number = alphabet.indexOf(source.charAt(index));
    const second: number = alphabet.indexOf(source.charAt(index + 1));
    const third: number = alphabet.indexOf(source.charAt(index + 2));
    const fourth: number = alphabet.indexOf(source.charAt(index + 3));
    const bytes: number[] = [(first << 2) | (second >> 4)];
    if (source.charAt(index + 2) !== '=') {
      bytes.push(((second & 15) << 4) | (third >> 2));
    }
    if (source.charAt(index + 3) !== '=') {
      bytes.push(((third & 3) << 6) | fourth);
    }
    for (let byteIndex: number = 0; byteIndex < bytes.length; byteIndex++) {
      encoded += '%' + bytes[byteIndex].toString(16).padStart(2, '0');
    }
  }
  let decoded: string = '';
  try {
    decoded = decodeURIComponent(encoded);
  } catch (error) {
    throw new Error('解码后的数据不是有效的 UTF-8 文本。');
  }
  if (encodeBase64(decoded) !== source) {
    throw new Error('Base64 的末尾补位不规范，请检查输入。');
  }
  return decoded;
}

export function convertUrl(input: string, decode: boolean): string {
  try {
    return decode ? decodeURIComponent(input) : encodeURIComponent(input);
  } catch (error) {
    throw new Error('URL 编码不正确，请检查 % 后的十六进制或无效的 Unicode 字符。');
  }
}

function padded(value: number, length: number = 2): string {
  return value.toString().padStart(length, '0');
}

export function convertTimestamp(input: string, unit: string = 'auto'): TimestampConversion {
  const source: string = input.trim();
  let milliseconds: number = 0;
  if (/^-?\d+$/.test(source)) {
    const number: number = Number(source);
    if (!Number.isSafeInteger(number)) {
      throw new Error('时间戳超出安全整数范围。');
    }
    const isMilliseconds: boolean = unit === 'ms' || (unit === 'auto' && source.replace('-', '').length > 10);
    milliseconds = isMilliseconds ? number : number * 1000;
  } else {
    const dateMatch: RegExpMatchArray | null = source.match(
      /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?(Z|[+-]\d{2}:\d{2})?$/);
    if (!dateMatch) {
      throw new Error('请输入秒/毫秒时间戳，或 YYYY-MM-DD HH:mm:ss（可带 Z / +08:00）。');
    }
    const year: number = Number(dateMatch[1]);
    const month: number = Number(dateMatch[2]);
    const day: number = Number(dateMatch[3]);
    const days: number[] = [31, year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28,
      31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month < 1 || month > 12 || day < 1 || day > days[month - 1] || Number(dateMatch[4]) > 23 ||
      Number(dateMatch[5]) > 59 || Number(dateMatch[6] || '0') > 59) {
      throw new Error('日期或时间无效，请检查月份、天数和时分秒。');
    }
    milliseconds = new Date(source.replace(' ', 'T')).getTime();
  }
  const date: Date = new Date(milliseconds);
  if (!Number.isFinite(milliseconds) || !Number.isFinite(date.getTime())) {
    throw new Error('无法转换该时间，请检查时间戳范围或时区格式。');
  }
  const result: TimestampConversion = new TimestampConversion();
  result.milliseconds = date.getTime().toString();
  result.seconds = Math.floor(date.getTime() / 1000).toString();
  const offset: number = -date.getTimezoneOffset();
  const zone: string = (offset >= 0 ? '+' : '-') + padded(Math.floor(Math.abs(offset) / 60)) + ':' +
    padded(Math.abs(offset) % 60);
  result.local = padded(date.getFullYear(), 4) + '-' + padded(date.getMonth() + 1) + '-' + padded(date.getDate()) +
    ' ' + padded(date.getHours()) + ':' + padded(date.getMinutes()) + ':' + padded(date.getSeconds()) +
    '.' + padded(date.getMilliseconds(), 3) + ' ' + zone;
  result.utc = date.toISOString();
  return result;
}

function colorHex(value: number): string {
  return Math.round(value).toString(16).padStart(2, '0').toUpperCase();
}

export function convertColor(input: string): ColorConversion {
  const source: string = input.trim();
  let red: number = 0;
  let green: number = 0;
  let blue: number = 0;
  const rgb: RegExpMatchArray | null = source.match(/^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$/i);
  const hsl: RegExpMatchArray | null = source.match(
    /^hsl\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)%\s*,\s*(\d+(?:\.\d+)?)%\s*\)$/i);
  if (/^#?[0-9a-fA-F]{3}$/.test(source) || /^#?[0-9a-fA-F]{6}$/.test(source)) {
    let hex: string = source.replace('#', '');
    if (hex.length === 3) {
      hex = hex.charAt(0).repeat(2) + hex.charAt(1).repeat(2) + hex.charAt(2).repeat(2);
    }
    red = parseInt(hex.substring(0, 2), 16);
    green = parseInt(hex.substring(2, 4), 16);
    blue = parseInt(hex.substring(4, 6), 16);
  } else if (rgb) {
    red = Number(rgb[1]);
    green = Number(rgb[2]);
    blue = Number(rgb[3]);
    if (red > 255 || green > 255 || blue > 255) {
      throw new Error('RGB 的每个分量应在 0–255 之间。');
    }
  } else if (hsl) {
    const hue: number = ((Number(hsl[1]) % 360) + 360) % 360;
    const saturation: number = Number(hsl[2]) / 100;
    const lightness: number = Number(hsl[3]) / 100;
    if (!Number.isFinite(hue) || !Number.isFinite(saturation) || !Number.isFinite(lightness) ||
      saturation > 1 || lightness > 1) {
      throw new Error('HSL 的饱和度与亮度应在 0%–100% 之间。');
    }
    const chroma: number = (1 - Math.abs(2 * lightness - 1)) * saturation;
    const x: number = chroma * (1 - Math.abs((hue / 60) % 2 - 1));
    const m: number = lightness - chroma / 2;
    const segments: number[][] = [[chroma, x, 0], [x, chroma, 0], [0, chroma, x],
      [0, x, chroma], [x, 0, chroma], [chroma, 0, x]];
    const segment: number[] = segments[Math.floor(hue / 60)];
    red = Math.round((segment[0] + m) * 255);
    green = Math.round((segment[1] + m) * 255);
    blue = Math.round((segment[2] + m) * 255);
  } else {
    throw new Error('支持 #RGB、#RRGGBB、rgb(33, 112, 240) 或 hsl(217, 87%, 54%)。');
  }
  const r: number = red / 255;
  const g: number = green / 255;
  const b: number = blue / 255;
  const max: number = Math.max(r, g, b);
  const min: number = Math.min(r, g, b);
  const delta: number = max - min;
  const lightness: number = (max + min) / 2;
  let hue: number = 0;
  if (delta !== 0) {
    if (max === r) {
      hue = ((g - b) / delta) % 6;
    } else if (max === g) {
      hue = (b - r) / delta + 2;
    } else {
      hue = (r - g) / delta + 4;
    }
    hue = (hue * 60 + 360) % 360;
  }
  const saturation: number = delta === 0 ? 0 : delta / (1 - Math.abs(2 * lightness - 1));
  const result: ColorConversion = new ColorConversion();
  result.hex = '#' + colorHex(red) + colorHex(green) + colorHex(blue);
  result.rgb = 'rgb(' + red + ', ' + green + ', ' + blue + ')';
  result.hsl = 'hsl(' + Math.round(hue * 10) / 10 + ', ' + Math.round(saturation * 1000) / 10 +
    '%, ' + Math.round(lightness * 1000) / 10 + '%)';
  return result;
}

export function compareLines(before: string, after: string): DiffLine[] {
  const left: string[] = before.replace(/\r\n/g, '\n').split('\n');
  const right: string[] = after.replace(/\r\n/g, '\n').split('\n');
  if (left.length > 300 || right.length > 300 || before.length + after.length > 40000) {
    throw new Error('文本对比每侧最多 300 行，总计最多 40,000 个字符。');
  }
  const matrix: number[][] = [];
  for (let index: number = 0; index <= left.length; index++) {
    matrix.push(new Array<number>(right.length + 1).fill(0));
  }
  for (let i: number = left.length - 1; i >= 0; i--) {
    for (let j: number = right.length - 1; j >= 0; j--) {
      matrix[i][j] = left[i] === right[j] ? matrix[i + 1][j + 1] + 1 :
        Math.max(matrix[i + 1][j], matrix[i][j + 1]);
    }
  }
  const output: DiffLine[] = [];
  let i: number = 0;
  let j: number = 0;
  while (i < left.length || j < right.length) {
    if (i < left.length && j < right.length && left[i] === right[j]) {
      output.push(new DiffLine('equal', left[i], i + 1, j + 1));
      i++;
      j++;
    } else if (i < left.length && (j === right.length || matrix[i + 1][j] >= matrix[i][j + 1])) {
      output.push(new DiffLine('remove', left[i], i + 1, 0));
      i++;
    } else {
      output.push(new DiffLine('add', right[j], 0, j + 1));
      j++;
    }
  }
  return output;
}

/** Call on a background task. The UI applies an execution timeout. */
export function testRegex(pattern: string, flags: string, input: string): string {
  if (pattern.length === 0) {
    throw new Error('请输入正则表达式，不包含开头与结尾的 /。');
  }
  if (pattern.length > 500 || input.length > 20000) {
    throw new Error('正则最多 500 个字符，测试文本最多 20,000 个字符。');
  }
  if (!/^[gimsu]*$/.test(flags) || new Set<string>(flags.split('')).size !== flags.length) {
    throw new Error('标志支持 g、i、m、s、u，且不能重复。');
  }
  const expression: RegExp = new RegExp(pattern, flags);
  const matches: string[] = [];
  let match: RegExpExecArray | null = expression.exec(input);
  while (match !== null && matches.length < 200) {
    let line: string = '[' + match.index + '–' + (match.index + match[0].length) + '] ' + JSON.stringify(match[0]);
    for (let index: number = 1; index < match.length; index++) {
      line += '\n    分组 ' + index + ': ' + (match[index] === undefined ? '未参与匹配' : JSON.stringify(match[index]));
    }
    matches.push(line);
    if (!expression.global) {
      break;
    }
    if (match[0].length === 0) {
      // Advance by a complete code point with Unicode matching to avoid looping
      // on the low surrogate of an astral character.
      const code: number = input.charCodeAt(expression.lastIndex);
      expression.lastIndex += expression.unicode && code >= 0xD800 && code <= 0xDBFF ? 2 : 1;
    }
    match = expression.exec(input);
  }
  if (matches.length === 0) {
    return '没有找到匹配项。';
  }
  return '找到 ' + matches.length + (matches.length === 200 ? ' 项（最多展示 200 项）' : ' 项匹配') +
    '\n位置按 UTF-16 字符索引计数，从 0 开始。\n\n' + matches.join('\n\n');
}

export function markdownInlines(input: string): MarkdownInline[] {
  const pattern: RegExp = /(\*\*[^*]+\*\*|__[^_]+__|`[^`]+`|\*[^*]+\*|_[^_]+_|\[[^\]]+\]\([^)]+\))/g;
  const output: MarkdownInline[] = [];
  let position: number = 0;
  let match: RegExpExecArray | null = pattern.exec(input);
  while (match !== null) {
    if (match.index > position) {
      output.push(new MarkdownInline(input.substring(position, match.index)));
    }
    const token: string = match[0];
    if (token.startsWith('**') || token.startsWith('__')) {
      output.push(new MarkdownInline(token.substring(2, token.length - 2), 'bold'));
    } else if (token.startsWith('`')) {
      output.push(new MarkdownInline(token.substring(1, token.length - 1), 'code'));
    } else if (token.startsWith('[')) {
      output.push(new MarkdownInline(token.substring(1, token.indexOf(']')), 'link'));
    } else {
      output.push(new MarkdownInline(token.substring(1, token.length - 1), 'italic'));
    }
    position = match.index + token.length;
    match = pattern.exec(input);
  }
  if (position < input.length) {
    output.push(new MarkdownInline(input.substring(position)));
  }
  return output;
}

export function parseMarkdown(input: string): MarkdownBlock[] {
  const source: string = input.substring(0, 30000);
  const lines: string[] = source.replace(/\r\n/g, '\n').split('\n');
  const blocks: MarkdownBlock[] = [];
  let inCode: boolean = false;
  let code: string = '';
  let paragraph: string = '';
  for (let index: number = 0; index < lines.length; index++) {
    const line: string = lines[index];
    const isFence: boolean = /^\s*```/.test(line);
    if (!inCode && (line.trim().length === 0 || isFence || /^(#{1,6} |[-*+] |\d+\. |> |---+$)/.test(line))) {
      if (paragraph.length > 0) {
        blocks.push(new MarkdownBlock('paragraph', paragraph));
        paragraph = '';
      }
    }
    if (isFence) {
      if (inCode) {
        blocks.push(new MarkdownBlock('code', code.replace(/\n$/, '')));
        code = '';
      }
      inCode = !inCode;
    } else if (inCode) {
      code += line + '\n';
    } else if (/^#{1,6} /.test(line)) {
      const marker: number = line.indexOf(' ');
      blocks.push(new MarkdownBlock('h' + marker, line.substring(marker + 1)));
    } else if (/^[-*+] /.test(line)) {
      blocks.push(new MarkdownBlock('list', '•  ' + line.substring(2)));
    } else if (/^\d+\. /.test(line)) {
      blocks.push(new MarkdownBlock('list', line));
    } else if (/^> /.test(line)) {
      blocks.push(new MarkdownBlock('quote', line.substring(2)));
    } else if (/^---+$/.test(line.trim())) {
      blocks.push(new MarkdownBlock('rule', ''));
    } else if (line.trim().length > 0) {
      paragraph += (paragraph.length > 0 ? '\n' : '') + line;
    }
  }
  if (paragraph.length > 0) {
    blocks.push(new MarkdownBlock('paragraph', paragraph));
  }
  if (inCode) {
    blocks.push(new MarkdownBlock('code', code.replace(/\n$/, '')));
  }
  return blocks;
}

export function suggestTool(input: string): string {
  const value: string = input.trim();
  if (value.startsWith('{') || value.startsWith('[')) {
    try {
      JSON.parse(value);
      return 'json';
    } catch (error) {
      return '';
    }
  }
  if (/^#(?:[\da-fA-F]{3}|[\da-fA-F]{6})$/.test(value) || /^(rgb|hsl)\(/i.test(value)) {
    return 'color';
  }
  if (/^-?(?:\d{10}|\d{13})$/.test(value)) {
    return 'timestamp';
  }
  return '';
}
