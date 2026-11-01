import { afterAll, beforeAll, describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { relationalStore } from '@kit.ArkData';
import { image } from '@kit.ImageKit';
import { pdfService } from '@kit.PDFKit';
import { openPDF } from '../../../main/ets/features/files/NativeFileOperations';
import { application } from '@kit.AbilityKit';
import { DeveloperRuntime } from '../../../main/ets/features/developer/DeveloperRuntime';
import { LumiNativeFixtures, LumiNativeImage, LumiNativePdfPage, LumiNativeResult } from './NativeFixtures';

let nativeScope: LumiNativeFixtures | undefined = undefined;

function scope(): LumiNativeFixtures {
  if (!nativeScope) { throw new Error('Native test fixtures were not initialized'); }
  return nativeScope;
}

function nativeCase(name: string, operation: () => Promise<void>): void {
  it(name, 0, async (): Promise<void> => {
    const started = Date.now();
    const result = new LumiNativeResult();
    result.name = name;
    try {
      await operation();
      result.passed = true;
      result.message = 'Real SDK integration assertions passed';
    } catch (error) {
      result.message = (error as Error)?.message || 'Native integration assertion failed';
      result.stack = (error as Error)?.stack || '';
      throw new Error(`${name}: ${result.message}\n${result.stack}`);
    } finally {
      result.elapsedMs = Date.now() - started;
      scope().report.results.push(result);
      await scope().writeReport();
    }
  });
}

function checkMarker(page: LumiNativePdfPage, marker: string, width: number, height: number): void {
  expect(page.text.replace(/\s/g, '').includes(marker)).assertTrue();
  expect(Math.round(page.width)).assertEqual(width);
  expect(Math.round(page.height)).assertEqual(height);
  expect(page.textObjects > 0 || page.formObjects > 0).assertTrue();
  // A structural PDF operation must preserve searchable text objects, rather than rasterize the page.
  expect(page.imageObjects).assertEqual(0);
}

function checkPattern(decoded: LumiNativeImage, width: number, height: number): void {
  expect(decoded.width).assertEqual(width);
  expect(decoded.height).assertEqual(height);
  const left = (Math.floor(height / 2) * width + Math.floor(width / 4)) * 4;
  const right = (Math.floor(height / 2) * width + Math.floor(width * 3 / 4)) * 4;
  expect(decoded.rgba[left] > 150 && decoded.rgba[left + 2] < 130).assertTrue();
  expect(decoded.rgba[right] < 130 && decoded.rgba[right + 2] > 150).assertTrue();
  expect(decoded.rgba[left + 3]).assertEqual(255);
}

async function valueAt(database: relationalStore.RdbStore, key: string): Promise<string> {
  const rows = await database.querySql('SELECT value FROM validation_values WHERE id = ?', [key]);
  try { return rows.goToFirstRow() ? rows.getString(0) : ''; }
  finally { rows.close(); }
}

async function checkBytesUnchanged(path: string, expected: Uint8Array): Promise<void> {
  const actual = await scope().bytes(path);
  expect(actual.length).assertEqual(expected.length);
  expect(actual.every((value: number, index: number): boolean => value === expected[index])).assertTrue();
}

function checkNoOutputPrefix(outputName: string): void {
  expect(fs.accessSync(scope().path(outputName))).assertFalse();
  // Also catches split/render derivatives and temporary image artifacts, not just
  // the final nominal path. Every prefix belongs exclusively to this test run.
  expect(fs.listFileSync(scope().directory).some((name: string): boolean => name.startsWith(outputName))).assertFalse();
}

async function rejectInvalidPdfAcrossTools(path: string, prefix: string): Promise<void> {
  const invalidBefore = await scope().bytes(path);
  const validPath = scope().path('source_a.pdf');
  const validBefore = await scope().bytes(validPath);
  let openRejected = false;
  try {
    const document = openPDF(path, '');
    document.releaseDocument();
  } catch (error) { openRejected = true; }
  expect(openRejected).assertTrue();
  for (const tool of ['pdf-merge', 'pdf-split', 'pdf-extract', 'pdf-images']) {
    const outputName = prefix + '_' + tool.replace(/-/g, '_');
    const inputs = tool === 'pdf-merge' ? [validPath, path] : [path];
    let rejected = false;
    let message = '';
    try { await scope().process(tool, inputs, outputName); }
    catch (error) { rejected = true; message = (error as Error)?.message || ''; }
    expect(rejected).assertTrue();
    expect(message.length > 0).assertTrue();
    checkNoOutputPrefix(outputName);
    await checkBytesUnchanged(path, invalidBefore);
    await checkBytesUnchanged(validPath, validBefore);
  }
}

function checkNativeAnnotation(path: string, type: pdfService.AnnotationType): void {
  const document = new pdfService.PdfDocument();
  try {
    expect(document.loadDocument(path)).assertEqual(pdfService.ParseResult.PARSE_SUCCESS);
    expect(document.getPageCount()).assertEqual(1);
    const page = document.getPage(0);
    try {
      const annotations = page.getAnnotations();
      expect(annotations.length > 0).assertTrue();
      const annotation = annotations.find((candidate: pdfService.PdfAnnotation): boolean => candidate.type === type);
      if (!annotation) { throw new Error('The expected native annotation type was not parsed'); }
      const info = annotation.getAnnotationInfo();
      expect(info.type).assertEqual(type);
      if (type === pdfService.AnnotationType.TEXT) {
        expect(info.content || '').assertEqual('LumiKit native validation comment');
      } else {
        const action = info.action;
        if (!action) { throw new Error('The link fixture was not parsed as a real PDF action'); }
        expect(action.type).assertEqual(pdfService.PdfActionType.HYPERLINK);
        expect((action as pdfService.PdfActionHyperlink).hyperlink).assertEqual('https://example.invalid/lumikit-native-fixture');
      }
    } finally { page.release(); }
  } finally { document.releaseDocument(); }
}

async function rejectAnnotatedMergeBothOrders(path: string, prefix: string, type: pdfService.AnnotationType): Promise<void> {
  // Positive fixture validation ensures a malformed PDF cannot masquerade as an
  // annotation-policy rejection. The production message must identify its guard.
  checkNativeAnnotation(path, type);
  const sourceBefore = await scope().bytes(path);
  const validPath = scope().path('source_a.pdf');
  const validBefore = await scope().bytes(validPath);
  for (let position = 0; position < 2; position++) {
    const outputName = prefix + '_' + position.toString() + '.pdf';
    const inputs = position === 0 ? [path, validPath] : [validPath, path];
    let rejected = false;
    let message = '';
    try { await scope().process('pdf-merge', inputs, outputName); }
    catch (error) { rejected = true; message = (error as Error)?.message || ''; }
    expect(rejected).assertTrue();
    expect(message.includes('含链接或批注')).assertTrue();
    checkNoOutputPrefix(outputName);
    await checkBytesUnchanged(path, sourceBefore);
    await checkBytesUnchanged(validPath, validBefore);
    checkNativeAnnotation(path, type);
  }
}

export default function platformNativeTest(): void {
  describe('LumiKitNativeIntegration', (): void => {
    beforeAll(async (): Promise<void> => {
      const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().getApplicationContext();
      const moduleContext = await application.createModuleContext(appContext, 'entry');
      // RDB requires a genuine Stage module context, rather than the delegator's app-context wrapper.
      nativeScope = new LumiNativeFixtures(moduleContext);
      await nativeScope.initialize();
    });

    afterAll(async (): Promise<void> => {
      if (nativeScope) {
        let cleanupFailure = '';
        try { await nativeScope.cleanup(); }
        catch (error) { cleanupFailure = (error as Error)?.message || 'Native fixtures cleanup failed'; }
        const passed = nativeScope.report.results.filter((result: LumiNativeResult) => result.passed).length;
        await abilityDelegatorRegistry.getAbilityDelegator().print(
          `LUMIKIT_NATIVE_SUMMARY ${passed}/${nativeScope.report.results.length} passed; report=${nativeScope.reportPath}`);
        await abilityDelegatorRegistry.getAbilityDelegator().print(JSON.stringify(nativeScope.report));
        if (cleanupFailure) { throw new Error(cleanupFailure); }
      }
    });

    nativeCase('pngFixtureUsesActualImageKitPixels', async (): Promise<void> => {
      checkPattern(await scope().decode(scope().path('source.png')), 64, 40);
      const bytes = await scope().prefix(scope().path('source.png'), 8);
      expect(bytes.join(',')).assertEqual('137,80,78,71,13,10,26,10');
    });

    nativeCase('pngEncodeResizeRunsProductionTaskPool', async (): Promise<void> => {
      const output = await scope().process('image-convert', [scope().path('source.png')], 'converted.png', '', 'image/png', 32);
      expect(output.length).assertEqual(1);
      const decoded = await scope().decode(output[0]);
      checkPattern(decoded, 32, 20);
      expect(decoded.mime).assertEqual('image/png');
    });

    nativeCase('jpegEncodeResizeRunsProductionTaskPool', async (): Promise<void> => {
      const output = await scope().process('image-convert', [scope().path('source.png')], 'converted.jpg', '', 'image/jpeg', 32);
      const decoded = await scope().decode(output[0]);
      checkPattern(decoded, 32, 20);
      expect(decoded.mime).assertEqual('image/jpeg');
      const bytes = await scope().prefix(output[0], 3);
      expect(bytes[0]).assertEqual(255); expect(bytes[1]).assertEqual(216); expect(bytes[2]).assertEqual(255);
    });

    nativeCase('webpEncodeResizeRunsProductionTaskPool', async (): Promise<void> => {
      const packer = image.createImagePacker();
      try { expect(packer.supportedFormats.includes('image/webp')).assertTrue(); }
      finally { await packer.release(); }
      const output = await scope().process('image-convert', [scope().path('source.png')], 'converted.webp', '', 'image/webp', 32);
      const decoded = await scope().decode(output[0]);
      checkPattern(decoded, 32, 20);
      expect(decoded.mime).assertEqual('image/webp');
      const bytes = await scope().prefix(output[0], 12);
      expect(String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3])).assertEqual('RIFF');
      expect(String.fromCharCode(bytes[8], bytes[9], bytes[10], bytes[11])).assertEqual('WEBP');
    });

    nativeCase('pdfFixturePreservesSearchableVectorText', async (): Promise<void> => {
      const pages = scope().pdf(scope().path('source_a.pdf'));
      expect(pages.length).assertEqual(2);
      checkMarker(pages[0], 'Native-A1', 160, 200);
      checkMarker(pages[1], 'Native-A2', 220, 180);
    });

    nativeCase('pdfMergePreservesOrderDimensionsAndTextObjects', async (): Promise<void> => {
      const output = await scope().process('pdf-merge', [scope().path('source_a.pdf'), scope().path('source_b.pdf')], 'merged.pdf');
      expect(output.length).assertEqual(1);
      const pages = scope().pdf(output[0]);
      expect(pages.length).assertEqual(3);
      checkMarker(pages[0], 'Native-A1', 160, 200);
      checkMarker(pages[1], 'Native-A2', 220, 180);
      checkMarker(pages[2], 'Native-B1', 120, 240);
      expect(scope().pdf(scope().path('source_a.pdf')).length).assertEqual(2);
      expect(scope().pdf(scope().path('source_b.pdf')).length).assertEqual(1);
    });

    nativeCase('pdfSplitCreatesSeparateSearchableDocuments', async (): Promise<void> => {
      const output = await scope().process('pdf-split', [scope().path('source_a.pdf')], 'split', '1-2');
      expect(output.length).assertEqual(2);
      const first = scope().pdf(output[0]);
      const second = scope().pdf(output[1]);
      expect(first.length).assertEqual(1); expect(second.length).assertEqual(1);
      checkMarker(first[0], 'Native-A1', 160, 200);
      checkMarker(second[0], 'Native-A2', 220, 180);
    });

    nativeCase('pdfExtractKeepsOnlyRequestedPage', async (): Promise<void> => {
      const output = await scope().process('pdf-extract', [scope().path('source_a.pdf')], 'extracted.pdf', '2');
      expect(output.length).assertEqual(1);
      const pages = scope().pdf(output[0]);
      expect(pages.length).assertEqual(1);
      checkMarker(pages[0], 'Native-A2', 220, 180);
      expect(pages[0].text.includes('Native-A1')).assertFalse();
    });

    nativeCase('pdfRenderProducesDecodablePngWithVisibleInk', async (): Promise<void> => {
      const output = await scope().process('pdf-images', [scope().path('source_a.pdf')], 'render', '2');
      expect(output.length).assertEqual(1);
      const decoded = await scope().decode(output[0]);
      expect(decoded.mime).assertEqual('image/png');
      expect(decoded.width > 0 && decoded.height > 0).assertTrue();
      let ink = false;
      let paper = false;
      for (let index = 0; index < decoded.rgba.length; index += 4) {
        if (decoded.rgba[index] < 220 || decoded.rgba[index + 1] < 220 || decoded.rgba[index + 2] < 220) { ink = true; }
        if (decoded.rgba[index] > 250 && decoded.rgba[index + 1] > 250 && decoded.rgba[index + 2] > 250) { paper = true; }
      }
      expect(ink && paper).assertTrue();
    });

    nativeCase('imagesToPdfCreatesOneA4ImagePagePerInput', async (): Promise<void> => {
      const output = await scope().process('images-pdf', [scope().path('source.png'), scope().path('source.png')], 'images.pdf');
      expect(output.length).assertEqual(1);
      const pages = scope().pdf(output[0]);
      expect(pages.length).assertEqual(2);
      pages.forEach((page: LumiNativePdfPage): void => {
        expect(Math.round(page.width)).assertEqual(595);
        expect(Math.round(page.height)).assertEqual(842);
        expect(page.imageObjects > 0).assertTrue();
      });
    });

    nativeCase('invalidPageRangeRejectsWithoutPublishingOutput', async (): Promise<void> => {
      let rejected = false;
      try { await scope().process('pdf-extract', [scope().path('source_a.pdf')], 'invalid_extract.pdf', '3'); }
      catch (error) { rejected = true; }
      expect(rejected).assertTrue();
      expect(fs.accessSync(scope().path('invalid_extract.pdf'))).assertFalse();
      expect(scope().pdf(scope().path('source_a.pdf')).length).assertEqual(2);
    });

    nativeCase('damagedPdfRejectedAcrossPdfToolsWithoutPublishingOrMutatingSources', async (): Promise<void> => {
      const damaged = await scope().makeInvalidPdf('damaged_input.pdf', true);
      await rejectInvalidPdfAcrossTools(damaged, 'reject_damaged');
    });

    nativeCase('plainTextNamedPdfRejectedAcrossPdfToolsWithoutPublishingOrMutatingSources', async (): Promise<void> => {
      const plain = await scope().makeInvalidPdf('plain_text_input.pdf', false);
      await rejectInvalidPdfAcrossTools(plain, 'reject_plain_text');
    });

    nativeCase('pngNamedPdfRejectedAcrossPdfToolsWithoutPublishingOrMutatingSources', async (): Promise<void> => {
      const renamed = scope().path('png_input_named_pdf.pdf');
      const pngBefore = await scope().bytes(scope().path('source.png'));
      await scope().write(renamed, pngBefore);
      await rejectInvalidPdfAcrossTools(renamed, 'reject_png_disguised');
      await checkBytesUnchanged(scope().path('source.png'), pngBefore);
    });

    nativeCase('realSdkTextAnnotationRejectsMergeBothOrdersAndPreservesSources', async (): Promise<void> => {
      const baseBefore = await scope().bytes(scope().path('source_b.pdf'));
      const annotated = scope().makeTextAnnotationPdf('sdk_text_annotation.pdf');
      await checkBytesUnchanged(scope().path('source_b.pdf'), baseBefore);
      await rejectAnnotatedMergeBothOrders(annotated, 'reject_sdk_annotation', pdfService.AnnotationType.TEXT);
    });

    nativeCase('realUriLinkPdfRejectsMergeBothOrdersAndPreservesSources', async (): Promise<void> => {
      const linked = await scope().makeHyperlinkPdf('uri_link_annotation.pdf');
      const pages = scope().pdf(linked);
      expect(pages.length).assertEqual(1);
      checkMarker(pages[0], 'Native-Link', 160, 200);
      await rejectAnnotatedMergeBothOrders(linked, 'reject_uri_link', pdfService.AnnotationType.LINK);
    });

    nativeCase('sha256UsesRealCryptoArchitectureKnownVectors', async (): Promise<void> => {
      expect(await DeveloperRuntime.sha256('')).assertEqual('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(await DeveloperRuntime.sha256('abc')).assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(await DeveloperRuntime.sha256('你好')).assertEqual('670d9743542cae3ea7ebe36af56bd53648b0a1126162e78d81a32934a711302e');
    });

    nativeCase('uuidUsesRealArkTsRandomVersion4Values', async (): Promise<void> => {
      const values = DeveloperRuntime.uuids(100).split('\n');
      expect(values.length).assertEqual(100);
      values.forEach((value: string, index: number): void => {
        expect(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)).assertTrue();
        expect(values.indexOf(value)).assertEqual(index);
      });
    });

    nativeCase('regexRunsRealTaskPoolWorker', async (): Promise<void> => {
      expect((await DeveloperRuntime.regex('Lumi(Kit)', 'g', 'LumiKit LumiKit')).includes('2')).assertTrue();
    });

    nativeCase('rdbPersistsUnicodeAndQuotedTextAfterCloseReopen', async (): Promise<void> => {
      const config = scope().database('persistence');
      let database = await relationalStore.getRdbStore(scope().context, config);
      const value = '集萤，SQLite\nquote\' and "double"';
      try {
        await database.executeSql('CREATE TABLE validation_values (id TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await database.insert('validation_values', { id: 'fixture', value: value });
      } finally { await database.close(); }
      database = await relationalStore.getRdbStore(scope().context, config);
      try { expect(await valueAt(database, 'fixture')).assertEqual(value); }
      finally { await database.close(); }
    });

    nativeCase('rdbRollsBackEveryWriteAndCommitsAtomicUpdates', async (): Promise<void> => {
      const config = scope().database('transaction');
      let database = await relationalStore.getRdbStore(scope().context, config);
      try {
        await database.executeSql('CREATE TABLE validation_values (id TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await database.insert('validation_values', { id: 'existing', value: 'before' });
        let failed = false;
        database.beginTransaction();
        try {
          await database.insert('validation_values', { id: 'temporary', value: 'must_rollback' });
          await database.executeSql("INSERT INTO validation_values (id, value) VALUES ('existing', 'conflict')");
        } catch (error) { failed = true; }
        finally { database.rollBack(); }
        expect(failed).assertTrue();
        expect(await valueAt(database, 'existing')).assertEqual('before');
        expect(await valueAt(database, 'temporary')).assertEqual('');
        database.beginTransaction();
        try {
          await database.insert('validation_values', { id: 'committed', value: 'kept' });
          await database.update({ value: 'after' }, new relationalStore.RdbPredicates('validation_values').equalTo('id', 'existing'));
          database.commit();
        } catch (error) {
          database.rollBack();
          throw new Error((error as Error)?.message || 'Native RDB commit failed');
        }
      } finally { await database.close(); }
      database = await relationalStore.getRdbStore(scope().context, config);
      try {
        expect(await valueAt(database, 'existing')).assertEqual('after');
        expect(await valueAt(database, 'committed')).assertEqual('kept');
        expect(await valueAt(database, 'temporary')).assertEqual('');
      } finally { await database.close(); }
    });
  });
}
