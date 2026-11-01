import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { pdfService } from '@kit.PDFKit';
import { fileIo } from '@kit.CoreFileKit';
import { FileService } from '../../core/FileService';
import { FormResponse, LocalForm } from './FormModels';
import { formPrintLines, paginatePrintLines, FormPrintLine } from './FormPrintLayout';

/** Text objects remain searchable; page content never depends on a UI screenshot. */
export class FormPdfService {
  static async create(context: common.UIAbilityContext, ui: UIContext, form: LocalForm,
    response?: FormResponse): Promise<string> {
    const fontInfo = new pdfService.FontInfo();
    const names: string[] = ['HarmonyOS Sans SC', 'HarmonyOS_Sans_SC', 'Noto Sans CJK SC', 'HarmonyOS Sans'];
    let family = 'HarmonyOS Sans';
    for (const name of names) {
      const font = ui.getFont().getFontByName(name);
      if (font && font.path) { fontInfo.fontPath = font.path; fontInfo.fontName = font.postScriptName; family = name; break; }
    }
    if (!fontInfo.fontPath) { throw new Error('未找到可用系统字体，暂时无法导出 PDF'); }
    const lines = formPrintLines(form, response, (text: string, size: number, bold: boolean): number => {
      return ui.getMeasureUtils().measureText({ textContent: text, fontFamily: family,
        fontSize: `${size}px`, fontWeight: bold ? FontWeight.Bold : FontWeight.Normal });
    });
    const pages = paginatePrintLines(lines);
    if (pages.length > 40) { throw new Error('PDF 超过 40 页，请拆分内容后重试'); }
    const document = new pdfService.PdfDocument();
    const filename = `${FileService.cleanName(response ? response.formTitle : form.title)}_${response ? '回答' : '空白模板'}.pdf`;
    const path = FileService.outputPath(context, filename);
    try {
      if (!document.createDocument(595, 842)) { throw new Error('无法创建 PDF'); }
      while (document.getPageCount() < pages.length) { document.insertBlankPage(document.getPageCount() - 1, 595, 842).release(); }
      pages.forEach((lines: FormPrintLine[], index: number) => {
        const page = document.getPage(index);
        try {
          let top = 52;
          lines.forEach((line: FormPrintLine) => {
            const style = new pdfService.TextStyle();
            style.fontInfo = fontInfo;
            style.textSize = line.size;
            style.textColor = line.muted ? 0x64748B : 0x1E293B;
            style.isBold = line.bold;
            if (line.text) { page.addTextObject(line.text, 44, 842 - top - line.size, style); }
            top += line.size * 1.6 + line.gap;
          });
          const footer = new pdfService.TextStyle();
          footer.fontInfo = fontInfo; footer.textSize = 9; footer.textColor = 0x64748B;
          page.addTextObject(`LumiKit · ${index + 1} / ${pages.length}`, 44, 32, footer);
        } finally { page.release(); }
      });
      if (!document.saveDocument(path)) { throw new Error('PDF 保存失败'); }
    } catch (error) {
      if (fileIo.accessSync(path)) { fileIo.unlinkSync(path); }
      throw new Error((error as Error)?.message || 'PDF 处理失败，请重试');
    } finally { document.releaseDocument(); }
    const verification = new pdfService.PdfDocument();
    try {
      if (verification.loadDocument(path) !== pdfService.ParseResult.PARSE_SUCCESS || verification.getPageCount() !== pages.length) {
        throw new Error('PDF 完整性校验失败');
      }
      const page = verification.getPage(0);
      try {
        if (!page.getTextContent().includes('LumiKit')) { throw new Error('PDF 文本校验失败，请重试'); }
      } finally { page.release(); }
    } catch (error) {
      if (fileIo.accessSync(path)) { fileIo.unlinkSync(path); }
      throw new Error((error as Error)?.message || 'PDF 处理失败，请重试');
    } finally { verification.releaseDocument(); }
    try { await FileService.register(context, path, filename); }
    catch (error) {
      if (fileIo.accessSync(path)) { fileIo.unlinkSync(path); }
      throw new Error((error as Error)?.message || 'PDF 处理失败，请重试');
    }
    return path;
  }
}
