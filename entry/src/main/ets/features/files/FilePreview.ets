import { fileUri } from '@kit.CoreFileKit';
import { PdfView, pdfViewManager, pdfService } from '@kit.PDFKit';
import { FileService } from '../../core/FileService';

/** Each preview owns its controller so another result cannot replace its document. */
@Component
export struct FilePreview {
  @Prop filePath: string = '';
  @Prop password: string = '';
  @State private previewLoading: boolean = false;
  @State private previewError: string = '';
  @State private imageAttempt: number = 0;
  private controller: pdfViewManager.PdfController | undefined = undefined;
  private disposed: boolean = false;
  private documentLoading: boolean = false;
  private documentLoaded: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    if (!this.filePath) {
      this.previewError = '未找到可预览的文件，请重新选择文件。';
      return;
    }
    if (this.isPDF()) {
      this.loadPDF();
    } else {
      this.previewLoading = true;
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
    // An in-flight load owns the controller until its promise settles.
    if (!this.documentLoading) {
      this.releasePDF();
    }
  }

  private isPDF(): boolean {
    return FileService.mime(this.filePath) === 'application/pdf';
  }

  private getController(): pdfViewManager.PdfController {
    if (!this.controller) {
      this.controller = new pdfViewManager.PdfController();
    }
    return this.controller;
  }

  private releasePDF(): void {
    this.documentLoaded = false;
    try {
      this.controller?.releaseDocument();
    } catch {
      // Closing a preview must finish even if the platform has already released it.
    }
  }

  private parseError(result: pdfService.ParseResult): string {
    if (result === pdfService.ParseResult.PARSE_ERROR_PASSWORD) {
      return 'PDF 密码错误或尚未填写，请修改密码后重新预览。';
    }
    if (result === pdfService.ParseResult.PARSE_ERROR_FILE) {
      return 'PDF 文件无法读取，请重新选择文件后重试。';
    }
    if (result === pdfService.ParseResult.PARSE_ERROR_FORMAT) {
      return 'PDF 文件格式无法解析，请检查文件是否完整。';
    }
    return 'PDF 预览失败，请检查文件后重试。';
  }

  private async loadPDF(): Promise<void> {
    if (this.disposed || this.documentLoading || this.documentLoaded) {
      return;
    }
    if (!canIUse('SystemCapability.OfficeService.PDFService.Core')) {
      this.previewError = '当前设备不支持 PDF 预览，请使用支持 PDF Kit 的设备。';
      return;
    }
    this.documentLoading = true;
    this.previewLoading = true;
    this.previewError = '';
    let releaseAfterLoad: boolean = false;
    try {
      const result = await this.getController().loadDocument(this.filePath, this.password);
      if (this.disposed) {
        releaseAfterLoad = true;
      } else if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
        releaseAfterLoad = true;
        this.previewError = this.parseError(result);
      } else {
        this.documentLoaded = true;
      }
    } catch {
      releaseAfterLoad = true;
      if (!this.disposed) {
        this.previewError = 'PDF 预览失败，请检查文件或密码后重试。';
      }
    } finally {
      this.documentLoading = false;
      if (this.disposed || releaseAfterLoad) {
        this.releasePDF();
      }
      if (!this.disposed) {
        this.previewLoading = false;
      }
    }
  }

  private retry(): void {
    if (this.disposed || this.previewLoading || !this.filePath) {
      return;
    }
    if (this.isPDF()) {
      this.loadPDF();
    } else {
      this.previewError = '';
      this.previewLoading = true;
      this.imageAttempt++;
    }
  }

  @Builder
  private loadingContent() {
    Column({ space: 10 }) {
      LoadingProgress().width(32).height(32).color($r('app.color.brand'))
      Text('正在加载预览…').fontSize(13).fontColor($r('app.color.text_secondary'))
    }.id('file-preview-loading').width('100%').height('100%')
      .justifyContent(FlexAlign.Center).backgroundColor($r('app.color.soft_surface'))
  }

  @Builder
  private errorContent() {
    Column({ space: 14 }) {
      Text(this.previewError).id('file-preview-error-message').fontSize(14).lineHeight(22)
        .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
      Button('重试').id('file-preview-retry').fontSize(13).height(40)
        .backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand'))
        .enabled(!this.previewLoading && this.filePath.length > 0).onClick(() => this.retry())
    }.id('file-preview-error').width('100%').height('100%').padding(20)
      .justifyContent(FlexAlign.Center).backgroundColor($r('app.color.soft_surface'))
  }

  build() {
    Column() {
      if (!this.filePath) {
        Stack() { this.errorContent() }.width('100%').height(300)
      } else if (this.isPDF()) {
        Stack() {
          if (canIUse('SystemCapability.OfficeService.PDFService.Core')) {
            PdfView({
              controller: this.getController(),
              pageLayout: pdfService.PageLayout.LAYOUT_SINGLE,
              isContinuous: true,
              showScroll: true,
              pageFit: pdfService.PageFit.FIT_WIDTH
            }).id('file-preview-pdf').width('100%').height(440)
          }
          if (this.previewLoading) { this.loadingContent() }
          if (this.previewError) { this.errorContent() }
        }.width('100%').height(440).borderRadius(14).clip(true)
      } else {
        Stack() {
          ForEach([this.imageAttempt], (attempt: number) => {
            Image(fileUri.getUriFromPath(this.filePath)).id('file-preview-image')
              .width('100%').height(300).objectFit(ImageFit.Contain)
              .onComplete(() => {
                if (!this.disposed && attempt === this.imageAttempt) {
                  this.previewLoading = false;
                  this.previewError = '';
                }
              })
              .onError(() => {
                if (!this.disposed && attempt === this.imageAttempt) {
                  this.previewLoading = false;
                  this.previewError = '图片预览失败，请检查文件后重试。';
                }
              })
          }, (attempt: number) => attempt.toString())
          if (this.previewLoading) { this.loadingContent() }
          if (this.previewError) { this.errorContent() }
        }.width('100%').height(300).borderRadius(14).clip(true)
      }
    }.id('file-preview-content').width('100%')
  }
}
