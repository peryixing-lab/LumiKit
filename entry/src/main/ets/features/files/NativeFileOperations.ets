import { image } from '@kit.ImageKit';
import { pdfService } from '@kit.PDFKit';
import { fileIo as fs } from '@kit.CoreFileKit';


export function parsePages(input: string, total: number): number[] {
  if (!input.trim()) { const all: number[] = []; for (let index = 0; index < total; index++) { all.push(index); } return all; }
  const pages: number[] = [];
  input.split(/[,，]/).forEach((part: string) => {
    const range = part.trim().split('-');
    if (range.length > 2 || !range.every((value: string) => /^\d+$/.test(value.trim()))) { throw new Error('页码格式示例：1-3,5,8'); }
    const start = Number(range[0]); const end = range.length === 2 ? Number(range[1]) : start;
    if (start < 1 || end > total || end < start) { throw new Error('页码超出文档范围，或起止顺序有误'); }
    for (let page = start; page <= end; page++) { if (!pages.includes(page - 1)) { pages.push(page - 1); } }
  });
  return pages.sort((a: number, b: number) => a - b);
}

export function openPDF(path: string, password: string): pdfService.PdfDocument {
  const document = new pdfService.PdfDocument();
  const result = document.loadDocument(path, password);
  if (result !== pdfService.ParseResult.PARSE_SUCCESS) { document.releaseDocument(); throw new Error('无法打开 PDF（错误 ' + result.toString() + '），请检查密码或文档完整性'); }
  return document;
}

export function savePDF(document: pdfService.PdfDocument, path: string, expected: number, password: string = ''): void {
  if (document.getPageCount() !== expected || !document.saveDocument(path)) { throw new Error('PDF 保存失败，请重试'); }
  const verification = openPDF(path, password);
  try { if (verification.getPageCount() !== expected) { throw new Error('输出 PDF 页数校验失败'); } } finally { verification.releaseDocument(); }
}

export async function encodeImage(input: string, output: string, format: string, quality: number, width: number): Promise<void> {
  const source = image.createImageSource(input);
  const packer = image.createImagePacker();
  try {
    const info = await source.getImageInfo();
    if (info.size.width * info.size.height > 40000000) { throw new Error('图片超过 4,000 万像素，请先缩小再导入'); }
    const ratio = width > 0 ? Math.min(1, width / info.size.width) : 1;
    const pixel = await source.createPixelMap({ desiredSize: { width: Math.max(1, Math.round(info.size.width * ratio)), height: Math.max(1, Math.round(info.size.height * ratio)) } });
    try {
      const bytes = await packer.packToData(pixel, { format: format, quality: quality });
      const file = fs.openSync(output, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, bytes); } finally { fs.closeSync(file); }
    } finally { await pixel.release(); }
  } finally { await source.release(); await packer.release(); }
}

