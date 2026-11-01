import { compressImage } from './ImageCompression';
import { compressPdf, organizePdf, LumiPdfPageEdit } from './PdfEnhancements';
import { image } from '@kit.ImageKit';
import { pdfService } from '@kit.PDFKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { parsePages, openPDF, savePDF, encodeImage } from './NativeFileOperations';

export interface ProcessingOptions { tool: string; inputs: string[]; outputs: string[]; pages: string; quality: number; width: number; format: string; password: string; targetBytes?: number; editPages?: LumiPdfPageEdit[]; }

/** Runs native processing in a task-pool thread. Only paths and scalar options cross the boundary. */
@Concurrent
export async function processFiles(options: ProcessingOptions): Promise<string[]> {
  const created: string[] = [];
  try {
    if (options.tool === 'pdf-compress' || options.tool === 'pdf-edit') {
      if (options.tool === 'pdf-compress') { await compressPdf(options.inputs[0], options.password, options.outputs[0], options.targetBytes || 0, options.quality); }
      else { organizePdf(options.inputs[0], options.password, options.outputs[0], options.editPages || []); }
      if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
      taskpool.Task.sendData(100); return [options.outputs[0]];
    }
    if (options.tool === 'image-compress') {
      for (let i = 0; i < options.inputs.length; i++) {
        if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
        taskpool.Task.sendData(Math.round(i / options.inputs.length * 95));
        if (await compressImage(options.inputs[i], options.outputs[i], options.format, options.quality, options.width, options.targetBytes || 0)) { created.push(options.outputs[i]); }
      }
      if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
      if (!created.length) { throw new Error('原图已较紧凑，本次设置未减小体积。原图已保留，可降低质量或宽度后重试'); }
      taskpool.Task.sendData(100); return created;
    }
    if (options.tool === 'image-convert') {
      for (let i = 0; i < options.inputs.length; i++) {
        if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
        taskpool.Task.sendData(Math.round(i / options.inputs.length * 90));
        await encodeImage(options.inputs[i], options.outputs[i], options.format, options.quality, options.width);
        created.push(options.outputs[i]);
      }
      if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
    taskpool.Task.sendData(100);
    return created;
    }
    if (options.tool === 'images-pdf') {
      const target = new pdfService.PdfDocument();
      if (!target.createDocument(595, 842)) { throw new Error('无法创建 PDF'); }
      try {
        for (let i = 0; i < options.inputs.length; i++) {
        if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
        taskpool.Task.sendData(Math.round(i / options.inputs.length * 90));
          const temporary = options.outputs[0] + '_image_' + i.toString() + '.jpg';
          await encodeImage(options.inputs[i], temporary, 'image/jpeg', options.quality, 2400);
          const source = image.createImageSource(temporary);
          try {
            const info = await source.getImageInfo();
            const ratio = Math.min(547 / info.size.width, 794 / info.size.height);
            const width = info.size.width * ratio; const height = info.size.height * ratio;
            const page = target.insertBlankPage(i, 595, 842);
            try { page.addImageObject(temporary, (595 - width) / 2, (842 - height) / 2, width, height); } finally { page.release(); }
          } finally { await source.release(); if (fs.accessSync(temporary)) { fs.unlinkSync(temporary); } }
        }
        target.deletePage(target.getPageCount() - 1, 1);
        savePDF(target, options.outputs[0], options.inputs.length); created.push(options.outputs[0]);
      } finally { target.releaseDocument(); }
      if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
    taskpool.Task.sendData(100);
    return created;
    }
    if (options.tool === 'pdf-merge') {
      const target = new pdfService.PdfDocument();
      if (!target.createDocument(595, 842)) { throw new Error('无法创建 PDF'); }
      let count: number = 0;
      try {
        for (let i = 0; i < options.inputs.length; i++) {
        if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
        taskpool.Task.sendData(Math.round(i / options.inputs.length * 90));
          const source = openPDF(options.inputs[i], options.password);
          try {
            for (let index = 0; index < source.getPageCount(); index++) {
              const page = source.getPage(index);
              try { if (page.getAnnotations().length > 0) { throw new Error('此 PDF 含链接或批注。系统结构合并不复制批注，为避免内容丢失已停止；请使用不含批注的副本'); } } finally { page.release(); }
            }
            const inserted = target.insertPageFromDocument(source, 0, source.getPageCount(), target.getPageCount() - 1);
            inserted.release(); count += source.getPageCount();
          } finally { source.releaseDocument(); }
        }
        target.deletePage(target.getPageCount() - 1, 1);
        savePDF(target, options.outputs[0], count, options.password); created.push(options.outputs[0]);
      } finally { target.releaseDocument(); }
      if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
    taskpool.Task.sendData(100);
    return created;
    }
    const source = openPDF(options.inputs[0], options.password);
    try {
      const pages = parsePages(options.pages, source.getPageCount());
      if (options.tool === 'pdf-images') {
        for (let i = 0; i < pages.length; i++) {
          if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
          taskpool.Task.sendData(Math.round(i / pages.length * 90));
          const page = source.getPage(pages[i]);
          try {
            const pixel = page.getPagePixelMap();
            const packer = image.createImagePacker();
            try {
              const bytes = await packer.packToData(pixel, { format: 'image/png', quality: 100 });
              const path = options.outputs[0] + '_page_' + (pages[i] + 1).toString() + '.png';
              const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
              try { fs.writeSync(file.fd, bytes); } finally { fs.closeSync(file); }
              created.push(path);
            } finally { await pixel.release(); await packer.release(); }
          } finally { page.release(); }
        }
      } else if (options.tool === 'pdf-split') {
        for (let i = 0; i < pages.length; i++) {
          if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
          taskpool.Task.sendData(Math.round(i / pages.length * 90));
          const document = openPDF(options.inputs[0], options.password);
          try {
            const total = document.getPageCount();
            if (pages[i] < total - 1) { document.deletePage(pages[i] + 1, total - pages[i] - 1); }
            if (pages[i] > 0) { document.deletePage(0, pages[i]); }
            const path = options.outputs[0] + '_page_' + (pages[i] + 1).toString() + '.pdf';
            savePDF(document, path, 1, options.password); created.push(path);
          } finally { document.releaseDocument(); }
        }
      } else {
        for (let i = source.getPageCount() - 1; i >= 0; i--) { if (!pages.includes(i)) { source.deletePage(i, 1); } }
        savePDF(source, options.outputs[0], pages.length, options.password); created.push(options.outputs[0]);
      }
    } finally { source.releaseDocument(); }
    if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
    taskpool.Task.sendData(100);
    return created;
  } catch (error) {
    options.outputs.forEach((prefix: string) => {
      const folder = prefix.substring(0, prefix.lastIndexOf('/'));
      const name = prefix.substring(prefix.lastIndexOf('/') + 1);
      fs.listFileSync(folder).filter((entry: string) => entry.startsWith(name)).forEach((entry: string) => { fs.unlinkSync(folder + '/' + entry); });
    });
    throw new Error((error as Error).message || '文件处理失败，请重试');
  }
}
