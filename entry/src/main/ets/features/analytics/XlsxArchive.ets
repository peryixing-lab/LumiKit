import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { LumiZipEntry } from './XlsxParser';
import { lumiCrc } from '../../core/PortableBackup';

export async function readXmlEntry(bytes: Uint8Array, entries: LumiZipEntry[], name: string, optional: boolean = false): Promise<string> {
  const entry = entries.find((candidate: LumiZipEntry) => candidate.name === name);
  if (!entry) { if (optional) { return ''; } throw new Error('Excel 缺少必要文件：' + name); }
  const compressed = bytes.slice(entry.offset, entry.offset + entry.compressed);
  let output: Uint8Array;
  if (entry.method === 0) { output = compressed; }
  else {
    const zip = await zlib.createZip();
    const stream: zlib.ZStream = { nextIn: compressed.buffer as ArrayBuffer, availableIn: compressed.length,
      nextOut: new ArrayBuffer(entry.size + 1), availableOut: entry.size + 1 };
    await zip.inflateInit2(stream, -15);
    try {
      const status = await zip.inflate(stream, zlib.CompressFlushMode.FINISH);
      const result = await zip.getZStream();
      if (status !== zlib.ReturnStatus.STREAM_END || result.totalOut !== entry.size || result.totalIn !== compressed.length || !stream.nextOut) {
        throw new Error('Excel 解压长度不符');
      }
      output = new Uint8Array(stream.nextOut, 0, entry.size);
    } finally { await zip.inflateEnd(stream); }
  }
  if (output.length !== entry.size || lumiCrc(output) !== entry.crc) { throw new Error('Excel 内容校验失败'); }
  return new util.TextDecoder().decodeToString(output);
}

