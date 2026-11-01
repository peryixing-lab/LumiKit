import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { openPDF, savePDF } from './NativeFileOperations';

export class LumiPdfPageEdit {
  original: number = 0;
  rotation: number = 0;
  thumbnail: string = '';
}
export function validatePdfOrder(pages: LumiPdfPageEdit[], total: number): void {
  const ids = new Set<number>();
  if (!pages.length || pages.length > total) { throw new Error('至少保留一页'); }
  for (const page of pages) {
    if (!Number.isInteger(page.original) || page.original < 0 || page.original >= total || ids.has(page.original) ||
      ![0, 90, 180, 270].includes(page.rotation)) { throw new Error('页面顺序或旋转角度无效，请重新载入'); }
    ids.add(page.original);
  }
}
@Concurrent
export async function preparePdfPages(path: string, password: string, prefix: string): Promise<LumiPdfPageEdit[]> {
  const source = openPDF(path, password);
  const results: LumiPdfPageEdit[] = [];
  try {
    if (source.getPageCount() > 200) { throw new Error('可视化整理最多 200 页，请先提取所需范围'); }
    for (let i = 0; i < source.getPageCount(); i++) {
      const page = source.getPage(i);
      try {
        const matrix = new pdfService.PdfMatrix(); matrix.x = 0; matrix.y = 0; matrix.width = 160; matrix.height = Math.max(1, Math.round(page.getHeight() / page.getWidth() * 160)); matrix.rotate = 0;
        const pixel = page.getAreaPixelMap(matrix, 160, Math.max(1, Math.round(page.getHeight() / page.getWidth() * 160)), false, true);
        if (!pixel) { throw new Error('页面缩略图渲染失败'); }
        const packer = image.createImagePacker();
        const thumbnail = prefix + '_' + i.toString() + '.jpg';
        try {
          const bytes = await packer.packToData(pixel, { format: 'image/jpeg', quality: 70 });
          const file = await fs.open(thumbnail, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          try { await fs.write(file.fd, bytes); } finally { await fs.close(file); }
        } finally { await pixel.release(); await packer.release(); }
        results.push({ original: i, rotation: 0, thumbnail: thumbnail });
      } finally { page.release(); }
    }
    return results;
  } finally { source.releaseDocument(); }
}
export function organizePdf(input: string, password: string, output: string, pages: LumiPdfPageEdit[]): void {
  const source = openPDF(input, password);
  try {
    const total = source.getPageCount(); validatePdfOrder(pages, total);
    const live: number[] = []; for (let i = 0; i < total; i++) { live.push(i); }
    for (let i = 0; i < pages.length; i++) {
      const position = live.indexOf(pages[i].original);
      // Only move backwards. SDK forward moves use a different destination convention.
      if (position !== i) { if (!source.movePage(position, i)) { throw new Error('页面移动失败'); } live.splice(i, 0, live.splice(position, 1)[0]); }
      const page = source.getPage(i);
      try { page.setRotation(((page.getRotation() + pages[i].rotation) % 360) as pdfService.RotationAngle); } finally { page.release(); }
    }
    if (pages.length < total) { source.deletePage(pages.length, total - pages.length); }
    savePDF(source, output, pages.length, password);
  } finally { source.releaseDocument(); }
}
/** Explicit image-based compression; the original remains unchanged. */
export async function compressPdf(input: string, password: string, output: string, targetBytes: number, quality: number): Promise<void> {
  const source = openPDF(input, password);
  const packer = image.createImagePacker();
  try {
    if (source.getPageCount() > 200) { throw new Error('压缩最多 200 页，请先拆分'); }
    for (let attempt = 0; attempt < 4; attempt++) {
      const target = new pdfService.PdfDocument();
      if (!target.createDocument(595, 842)) { throw new Error('无法创建压缩文档'); }
      try {
        for (let i = 0; i < source.getPageCount(); i++) {
          if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
          taskpool.Task.sendData(Math.round((attempt * source.getPageCount() + i) / (4 * source.getPageCount()) * 95));
          const page = source.getPage(i);
          const temporary = output + '_render.jpg';
          try {
            const width = page.getWidth(); const height = page.getHeight();
            const scale = Math.min(2 * Math.pow(0.75, attempt), 2200 / Math.max(width, height));
            const matrix = new pdfService.PdfMatrix(); matrix.x = 0; matrix.y = 0; matrix.width = Math.max(1, Math.round(width * scale)); matrix.height = Math.max(1, Math.round(height * scale)); matrix.rotate = 0;
            const pixel = page.getAreaPixelMap(matrix, Math.max(1, Math.round(width * scale)), Math.max(1, Math.round(height * scale)), false, true);
            if (!pixel) { throw new Error('PDF 页面渲染失败'); }
            try {
              const bytes = await packer.packToData(pixel, { format: 'image/jpeg', quality: Math.max(30, Math.round(quality) - attempt * 15) });
              const file = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
              try { await fs.write(file.fd, bytes); } finally { await fs.close(file); }
            } finally { await pixel.release(); }
            const inserted = target.insertBlankPage(i, width, height);
            try { inserted.addImageObject(temporary, 0, 0, width, height); } finally { inserted.release(); }
          } finally { page.release(); if (fs.accessSync(temporary)) { await fs.unlink(temporary); } }
        }
        target.deletePage(target.getPageCount() - 1, 1); savePDF(target, output, source.getPageCount());
      } finally { target.releaseDocument(); }
      if (!targetBytes || fs.statSync(output).size <= targetBytes) { break; }
    }
    if (fs.statSync(output).size >= fs.statSync(input).size) { throw new Error('原文件已较紧凑，本次压缩未减小体积。请保留原文件'); }
  } finally { source.releaseDocument(); await packer.release(); }
}
