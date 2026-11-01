import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { pdfService } from '@kit.PDFKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { taskpool, util } from '@kit.ArkTS';
import { window } from '@kit.ArkUI';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { relationalStore } from '@kit.ArkData';
import { processFiles, ProcessingOptions } from '../../../main/ets/features/files/FileProcessor';

export class LumiNativeImage {
  width: number = 0;
  height: number = 0;
  mime: string = '';
  rgba: Uint8Array = new Uint8Array(0);
}

export class LumiNativePdfPage {
  text: string = '';
  width: number = 0;
  height: number = 0;
  textObjects: number = 0;
  imageObjects: number = 0;
  formObjects: number = 0;
}

export class LumiNativeResult {
  name: string = '';
  passed: boolean = false;
  message: string = '';
  stack: string = '';
  elapsedMs: number = 0;
}

export class LumiNativeReport {
  suite: string = 'LumiKitNativeIntegration';
  startedAt: string = '';
  results: LumiNativeResult[] = [];
  fixturesRemoved: boolean = false;
  cleanupErrors: string[] = [];
}

/** All paths are owned by this run. This class never opens StorageService or the business database. */
export class LumiNativeFixtures {
  readonly context: common.Context;
  readonly runId: string = `${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  readonly base: string;
  readonly directory: string;
  readonly reportPath: string;
  readonly report: LumiNativeReport = new LumiNativeReport();
  private readonly databases: relationalStore.StoreConfig[] = [];
  private fontInfo: pdfService.FontInfo = new pdfService.FontInfo();

  constructor(context: common.Context) {
    this.context = context;
    this.base = `${context.cacheDir}/lumikit-validation`;
    this.directory = `${this.base}/run_${this.runId}`;
    this.reportPath = `${this.base}/report_${this.runId}.json`;
    this.report.startedAt = new Date().toISOString();
  }

  path(name: string): string {
    if (!/^[a-zA-Z0-9_.-]+$/.test(name)) { throw new Error('Invalid test fixture filename'); }
    return `${this.directory}/${name}`;
  }

  async initialize(): Promise<void> {
    await fs.mkdir(this.directory, true);
    if (!canIUse('SystemCapability.OfficeService.PDFService.Core')) {
      throw new Error('This native integration suite requires the real HarmonyOS PDF Kit capability');
    }
    try {
      const ui = (await window.getLastWindow(this.context)).getUIContext();
      for (const name of ['HarmonyOS Sans', 'HarmonyOS Sans SC', 'HarmonyOS_Sans_SC']) {
        const font = ui.getFont().getFontByName(name);
        if (font && font.path) { this.fontInfo.fontPath = font.path; this.fontInfo.fontName = font.postScriptName; break; }
      }
    } catch (error) {
      // A test runner can run without a foreground UIAbility. The standard system font is sufficient for ASCII fixtures.
    }
    if (!this.fontInfo.fontPath) {
      for (const path of ['/system/fonts/HarmonyOS_Sans.ttf', '/system/fonts/HarmonyOS_Sans_SC.ttf', '/system/fonts/Roboto-Regular.ttf']) {
        if (fs.accessSync(path)) { this.fontInfo.fontPath = path; break; }
      }
    }
    if (!this.fontInfo.fontPath) { this.fontInfo.fontName = 'Helvetica'; }
    await this.makePng(this.path('source.png'));
    this.makePdf(this.path('source_a.pdf'), ['Native-A1', 'Native-A2'], [160, 220], [200, 180]);
    this.makePdf(this.path('source_b.pdf'), ['Native-B1'], [120], [240]);
    await this.writeReport();
    await abilityDelegatorRegistry.getAbilityDelegator().print(`LUMIKIT_NATIVE_REPORT ${this.reportPath}`);
  }

  async write(path: string, bytes: Uint8Array): Promise<void> {
    if (!path.startsWith(this.base + '/')) { throw new Error('Refusing to write outside test fixture directory'); }
    const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      let offset = 0;
      while (offset < bytes.length) {
        const written = await fs.write(file.fd, bytes.slice(offset).buffer);
        if (written <= 0) { throw new Error('Native fixture write was incomplete'); }
        offset += written;
      }
    } finally { await fs.close(file); }
  }

  async prefix(path: string, length: number): Promise<Uint8Array> {
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const bytes = new ArrayBuffer(length);
      const read = await fs.read(file.fd, bytes);
      return new Uint8Array(bytes, 0, read);
    } finally { await fs.close(file); }
  }

  async bytes(path: string): Promise<Uint8Array> {
    if (!path.startsWith(this.directory + '/')) { throw new Error('Refusing to read outside this run fixture directory'); }
    const length = (await fs.stat(path)).size;
    const bytes = new Uint8Array(length);
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      let offset = 0;
      while (offset < length) {
        const chunk = new ArrayBuffer(length - offset);
        // No offset option: the descriptor's file pointer advances after each read.
        const count = await fs.read(file.fd, chunk);
        if (count <= 0) { throw new Error('Native fixture snapshot was incomplete'); }
        bytes.set(new Uint8Array(chunk, 0, count), offset);
        offset += count;
      }
      return bytes;
    } finally { await fs.close(file); }
  }

  async makeInvalidPdf(name: string, damagedHeader: boolean): Promise<string> {
    const path = this.path(name);
    const content = damagedHeader ?
      '%PDF-1.7\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n% Missing pages, xref, trailer and EOF intentionally.\n' :
      'LumiKit QA plain text, deliberately named .pdf. This is not a PDF document.\n';
    await this.write(path, new util.TextEncoder().encodeInto(content));
    return path;
  }

  makeTextAnnotationPdf(name: string): string {
    const path = this.path(name);
    const document = new pdfService.PdfDocument();
    try {
      if (document.loadDocument(this.path('source_b.pdf')) !== pdfService.ParseResult.PARSE_SUCCESS) {
        throw new Error('Cannot load the source for a real SDK text annotation');
      }
      const page = document.getPage(0);
      try {
        const note = new pdfService.TextAnnotationInfo();
        note.type = pdfService.AnnotationType.TEXT;
        note.uniqueId = 'lumikit-native-note-' + this.runId;
        note.content = 'LumiKit native validation comment';
        note.title = 'LumiKit native test';
        note.iconName = 'Note';
        note.state = pdfService.TextAnnotationState.UNMARKED;
        note.x = 20; note.y = 60;
        page.addAnnotation(note);
      } finally { page.release(); }
      if (!document.saveDocument(path)) { throw new Error('Cannot save the real SDK text annotation fixture'); }
      return path;
    } finally { document.releaseDocument(); }
  }

  async makeHyperlinkPdf(name: string): Promise<string> {
    // The installed SDK declares PdfAnnotationInfo.action as read-only in behavior:
    // links can be inspected, but cannot be added/edited. Use a tiny standards-based
    // PDF file as input instead of inventing an unsupported PDF Kit write method.
    // The test must independently confirm that PDF Kit parses its LINK + URI action.
    const content = 'BT /F1 12 Tf 12 160 Td (Native-Link) Tj ET\n';
    const objects: string[] = [
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 160 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R /Annots [6 0 R] >>',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
      '<< /Length ' + content.length.toString() + ' >>\nstream\n' + content + 'endstream',
      '<< /Type /Annot /Subtype /Link /Rect [12 145 110 175] /Border [0 0 0] /NM (lumikit-native-link) /A << /Type /Action /S /URI /URI (https://example.invalid/lumikit-native-fixture) >> >>'
    ];
    let pdf = '%PDF-1.4\n';
    const offsets: number[] = [];
    objects.forEach((object: string, index: number): void => {
      offsets.push(pdf.length);
      pdf += (index + 1).toString() + ' 0 obj\n' + object + '\nendobj\n';
    });
    const xref = pdf.length;
    pdf += 'xref\n0 ' + (objects.length + 1).toString() + '\n0000000000 65535 f \n';
    offsets.forEach((offset: number): void => { pdf += offset.toString().padStart(10, '0') + ' 00000 n \n'; });
    pdf += 'trailer\n<< /Size ' + (objects.length + 1).toString() + ' /Root 1 0 R >>\nstartxref\n' + xref.toString() + '\n%%EOF\n';
    if (/[^\x00-\x7F]/.test(pdf)) { throw new Error('Link fixture offsets require ASCII bytes'); }
    const path = this.path(name);
    await this.write(path, new util.TextEncoder().encodeInto(pdf));
    return path;
  }

  private async makePng(path: string): Promise<void> {
    const width = 64;
    const height = 40;
    const data = new Uint8Array(width * height * 4);
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const index = (y * width + x) * 4;
        data[index] = x < width / 2 ? 220 : 24;
        data[index + 1] = 40;
        data[index + 2] = x < width / 2 ? 48 : 220;
        data[index + 3] = 255;
      }
    }
    const pixel = await image.createPixelMap(data.buffer, { size: { width: width, height: height },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888, pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.OPAQUE });
    const packer = image.createImagePacker();
    try { await this.write(path, new Uint8Array(await packer.packToData(pixel, { format: 'image/png', quality: 100 }))); }
    finally { await pixel.release(); await packer.release(); }
  }

  private makePdf(path: string, markers: string[], widths: number[], heights: number[]): void {
    const document = new pdfService.PdfDocument();
    try {
      if (!document.createDocument(160, 200)) { throw new Error('Native PDF fixture creation failed'); }
      markers.forEach((marker: string, index: number) => {
        const page = document.insertBlankPage(index, widths[index], heights[index]);
        try {
          const style = new pdfService.TextStyle();
          style.fontInfo = this.fontInfo;
          style.textSize = 10;
          style.textColor = 0x3068DB;
          page.addTextObject(marker, 12, 36, style);
        } finally { page.release(); }
      });
      document.deletePage(document.getPageCount() - 1, 1);
      if (!document.saveDocument(path)) { throw new Error('Native PDF fixture could not be saved'); }
    } finally { document.releaseDocument(); }
  }

  async process(tool: string, inputs: string[], output: string, pages: string = '',
    format: string = 'image/png', width: number = 0): Promise<string[]> {
    const options: ProcessingOptions = { tool: tool, inputs: inputs, outputs: [this.path(output)],
      pages: pages, quality: 92, width: width, format: format, password: '' };
    const task = new taskpool.Task(processFiles, options);
    task.onReceiveData((_progress: number): void => {});
    return await taskpool.execute(task, { timeout: 120000 }) as string[];
  }

  pdf(path: string): LumiNativePdfPage[] {
    const document = new pdfService.PdfDocument();
    try {
      if (document.loadDocument(path) !== pdfService.ParseResult.PARSE_SUCCESS) { throw new Error('Native PDF round trip could not load output'); }
      const result: LumiNativePdfPage[] = [];
      for (let index = 0; index < document.getPageCount(); index++) {
        const page = document.getPage(index);
        try {
          const info = new LumiNativePdfPage();
          info.width = page.getWidth(); info.height = page.getHeight(); info.text = page.getTextContent();
          const objects = page.getGraphicsObjects();
          info.textObjects = objects.filter((object: pdfService.GraphicsObject) => object.type === pdfService.GraphicsObjectType.OBJECT_TEXT).length;
          info.imageObjects = objects.filter((object: pdfService.GraphicsObject) => object.type === pdfService.GraphicsObjectType.OBJECT_IMAGE).length;
          info.formObjects = objects.filter((object: pdfService.GraphicsObject) => object.type === pdfService.GraphicsObjectType.OBJECT_FORM).length;
          result.push(info);
        } finally { page.release(); }
      }
      return result;
    } finally { document.releaseDocument(); }
  }

  async decode(path: string): Promise<LumiNativeImage> {
    const source = image.createImageSource(path);
    try {
      const info = await source.getImageInfo();
      const pixel = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      try {
        const decoded = new LumiNativeImage();
        decoded.width = info.size.width; decoded.height = info.size.height; decoded.mime = info.mimeType;
        const buffer = new ArrayBuffer(decoded.width * decoded.height * 4);
        await pixel.readPixelsToBuffer(buffer);
        decoded.rgba = new Uint8Array(buffer);
        return decoded;
      } finally { await pixel.release(); }
    } finally { await source.release(); }
  }

  database(caseName: string): relationalStore.StoreConfig {
    const config: relationalStore.StoreConfig = { name: `lumikit_validation_${this.runId}_${caseName}.db`,
      securityLevel: relationalStore.SecurityLevel.S1, customDir: 'lumikit-validation' };
    this.databases.push(config);
    return config;
  }

  async writeReport(): Promise<void> {
    await this.write(this.reportPath, new util.TextEncoder().encodeInto(JSON.stringify(this.report, null, 2)));
  }

  async cleanup(): Promise<void> {
    for (const config of this.databases) {
      if (!config.name.startsWith(`lumikit_validation_${this.runId}_`)) { throw new Error('Refusing to remove another database'); }
      try { await relationalStore.deleteRdbStore(this.context, config); }
      catch (error) { this.report.cleanupErrors.push((error as Error)?.message || 'Test database cleanup failed'); }
    }
    // Directory name includes this run's generated token; siblings and all application files remain untouched.
    if (!this.directory.startsWith(this.base + '/run_')) { throw new Error('Refusing to remove non-test directory'); }
    try { if (fs.accessSync(this.directory)) { await fs.rmdir(this.directory); } }
    catch (error) { this.report.cleanupErrors.push((error as Error)?.message || 'Test file cleanup failed'); }
    this.report.fixturesRemoved = this.report.cleanupErrors.length === 0;
    await this.writeReport();
    if (!this.report.fixturesRemoved) { throw new Error(this.report.cleanupErrors.join('; ')); }
  }
}
