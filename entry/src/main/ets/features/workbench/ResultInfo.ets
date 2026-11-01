import { taskpool } from '@kit.ArkTS';
import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { openPDF } from '../files/NativeFileOperations';
export class LumiResultInfo { pages: number = 0; thumbnail: string = ''; }
@Concurrent
export async function inspectResult(path: string, thumbnail: string): Promise<LumiResultInfo> {
  const document = openPDF(path, '');
  try {
    const result: LumiResultInfo = { pages: document.getPageCount(), thumbnail: '' };
    if (result.pages < 1) { return result; }
    const page = document.getPage(0);
    try {
      const matrix = new pdfService.PdfMatrix(); matrix.x = 0; matrix.y = 0; matrix.width = 100; matrix.height = Math.max(1, Math.round(page.getHeight() / page.getWidth() * 100)); matrix.rotate = 0;
      const pixel = page.getAreaPixelMap(matrix, 100, Math.max(1, Math.round(page.getHeight() / page.getWidth() * 100)), false, true);
      if (!pixel) { return result; }
      const packer = image.createImagePacker();
      try {
        const bytes = await packer.packToData(pixel, { format: 'image/jpeg', quality: 65 });
        const file = fs.openSync(thumbnail, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try { fs.writeSync(file.fd, bytes); } finally { fs.closeSync(file); }
        result.thumbnail = thumbnail;
      } finally { await pixel.release(); await packer.release(); }
    } finally { page.release(); }
    return result;
  } finally { document.releaseDocument(); }
}
