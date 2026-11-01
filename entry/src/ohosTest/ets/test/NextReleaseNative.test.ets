import { afterAll, beforeAll, describe, expect, it } from '@ohos/hypium';
import { application, common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { taskpool, util } from '@kit.ArkTS';
import { UIContext, window } from '@kit.ArkUI';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { calendarManager } from '@kit.CalendarKit';
import { InventoryCalendar } from '../../../main/ets/features/inventory/InventoryCalendar';
import { notificationManager } from '@kit.NotificationKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { pdfService } from '@kit.PDFKit';
import { LumiNativeFixtures } from './NativeFixtures';
import { readXlsx } from '../../../main/ets/features/analytics/XlsxService';
import { LumiXlsxSheet } from '../../../main/ets/features/analytics/XlsxParser';
import { ChartExport } from '../../../main/ets/features/analytics/ChartExport';
import { OcrService } from '../../../main/ets/features/ocr/OcrService';
import { preparePdfPages, organizePdf, LumiPdfPageEdit } from '../../../main/ets/features/files/PdfEnhancements';
import { processFiles, ProcessingOptions } from '../../../main/ets/features/files/FileProcessor';
import { openPDF, savePDF } from '../../../main/ets/features/files/NativeFileOperations';

const NATIVE_XLSX: string = 'UEsDBBQAAAAIAEehU131xeNdfQAAAJsAAAAPAAAAeGwvd29ya2Jvb2sueG1sNY47EsIwDAWv4vEBUKCg8Dip0tBwB5HI2JPYykjic3xSkOrNzm7x4odleTAv7lvXpkF6n822AKBTpop64o3a7hJLRdtRnsAplYlGnl6VmsGl664gtKIVbprLpn6ImolM/+saVur9fS/e5EY09E5CmXsvt/nsYYhw9HAcGn5QSwMEFAAAAAgAR6FTXdTErVk/AAAAVwAAABoAAAB4bC9fcmVscy93b3JrYm9vay54bWwucmVsc7MJSs1JLMnMzyvOyCwotrNB5ip4ptgqFXmmGCophCQWpaeW2CqV5xdlF2ekppYU64MpQ72K3BwlfTsbfVRzAFBLAwQUAAAACABHoVNd0gvjcYAAAAACAQAAGAAAAHhsL3dvcmtzaGVldHMvc2hlZXQxLnhtbHWP0QqDMAxFf0X6uoeY7jUGlP3BvqDUikWxULP6+2vHUBnzKcnl3hwubSFO6+icMH3Gw4hhimGrYqNQMdmytKgqaZRfZr+4p8Ss+5VJ2IbeEeQwlBvs199d+ZOZXz8ByLCdqHeivvhQ16jv/5AlOjDekGBgSqwJ0pkAp35w1H4DUEsBAhQDFAAAAAgAR6FTXfXF4119AAAAmwAAAA8AAAAAAAAAAAAAAIABAAAAAHhsL3dvcmtib29rLnhtbFBLAQIUAxQAAAAIAEehU13UxK1ZPwAAAFcAAAAaAAAAAAAAAAAAAACAAaoAAAB4bC9fcmVscy93b3JrYm9vay54bWwucmVsc1BLAQIUAxQAAAAIAEehU13SC+NxgAAAAAIBAAAYAAAAAAAAAAAAAACAASEBAAB4bC93b3Jrc2hlZXRzL3NoZWV0MS54bWxQSwUGAAAAAAMAAwDLAAAA1wEAAAAA';
let nextUiContext: UIContext | undefined;
let nextScope: LumiNativeFixtures | undefined;
function fixture(): LumiNativeFixtures { if (!nextScope) { throw new Error('Fixtures not ready'); } return nextScope; }

export default function nextReleaseNativeTest(): void {
  describe('LumiKitNextReleaseNative', (): void => {
    beforeAll(async (): Promise<void> => {
      const context = await application.createModuleContext(abilityDelegatorRegistry.getAbilityDelegator().getAppContext().getApplicationContext(), 'entry');
      nextScope = new LumiNativeFixtures(context); await nextScope.initialize();
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility' };
      await delegator.addAbilityMonitor(monitor);
      try { await delegator.startAbility({ bundleName: 'com.lovexjy.LumiKit', abilityName: 'EntryAbility' });
        const ability = await delegator.waitAbilityMonitor(monitor, 10000);
        nextUiContext = (await window.getLastWindow(ability.context)).getUIContext();
      } finally { await delegator.removeAbilityMonitor(monitor); }
    });
    afterAll(async (): Promise<void> => { if (nextScope) { await nextScope.cleanup(); } });

    it('xlsxUsesNativeBoundedInflaterAndTaskPool', 0, async (): Promise<void> => {
      const path = fixture().path('native.xlsx'); await fixture().write(path, new util.Base64Helper().decodeSync(NATIVE_XLSX));
      const sheets = await taskpool.execute(readXlsx, path) as LumiXlsxSheet[];
      expect(sheets.length).assertEqual(1); expect(sheets[0].name).assertEqual('Native Data');
      expect(sheets[0].csv).assertEqual('"code","value"\r\n"00123","2"');
    });
    it('pdfOrganizerReordersRotatesAndPreservesText', 0, async (): Promise<void> => {
      const input = fixture().path('source_a.pdf'); const original = await fixture().bytes(input);
      const output = fixture().path('organized.pdf');
      const plan: LumiPdfPageEdit[] = [{ original: 1, rotation: 90, thumbnail: '' }, { original: 0, rotation: 0, thumbnail: '' }];
      organizePdf(input, '', output, plan);
      const document = openPDF(output, ''); const source = openPDF(input, '');
      try {
        expect(document.getPageCount()).assertEqual(2);
        const first = document.getPage(0); const oldSecond = source.getPage(1);
        try { expect(first.getRotation()).assertEqual(90); expect(first.getTextContent().replace(/\s/g, '')).assertEqual(oldSecond.getTextContent().replace(/\s/g, '')); }
        finally { first.release(); oldSecond.release(); }
      } finally { document.releaseDocument(); source.releaseDocument(); }
      const after = await fixture().bytes(input); expect(after.every((part: number, index: number): boolean => part === original[index])).assertTrue();
      organizePdf(input, '', fixture().path('one_page.pdf'), [{ original: 1, rotation: 0, thumbnail: '' }]);
      const single = openPDF(fixture().path('one_page.pdf'), ''); try { expect(single.getPageCount()).assertEqual(1); } finally { single.releaseDocument(); }
    });
    it('pdfThumbnailsAreActualDecodableImages', 0, async (): Promise<void> => {
      const pages = await taskpool.execute(preparePdfPages, fixture().path('source_a.pdf'), '', fixture().path('thumb')) as LumiPdfPageEdit[];
      expect(pages.length).assertEqual(2); const decoded = await fixture().decode(pages[0].thumbnail);
      expect(decoded.width > 0 && decoded.width <= 220).assertTrue(); expect(decoded.height > 0).assertTrue();
    });
    it('chartExportProducesHighResolutionPngForEveryChartType', 0, async (): Promise<void> => {
      for (let kind = 0; kind < 4; kind++) {
        if (!nextUiContext) { throw new Error('Chart requires an active UI context'); }
        let rendered: image.PixelMap | undefined;
        nextUiContext.runScopedTask(() => { rendered = ChartExport.render('Native chart', 'group', 'count', [{ label: 'Alpha', count: 2, sum: 20 }, { label: 'Beta', count: 3, sum: 30 }], kind, false); });
        if (!rendered) { throw new Error('Chart did not return pixels'); }
        const pixel = rendered;
        const info = await pixel.getImageInfo(); expect(info.size.width).assertEqual(1200); expect(info.size.height).assertEqual(900);
        const packer = image.createImagePacker();
        try { const output = await packer.packToData(pixel, { format: 'image/png', quality: 100 }); expect(output.byteLength > 1000).assertTrue(); }
        finally { await pixel.release(); await packer.release(); }
      }
    });
    it('ocrRecognizesTextFromNativeRenderedDocument', 0, async (): Promise<void> => {
      if (!nextUiContext) { throw new Error('OCR fixture requires an active UI context'); }
      let rendered: image.PixelMap | undefined;
      nextUiContext.runScopedTask(() => { rendered = ChartExport.render('Native OCR verification', 'group', 'count', [{ label: 'Alpha', count: 2, sum: 2 }], 0, false); });
      if (!rendered) { throw new Error('Cannot render OCR fixture'); }
      const pixel = rendered; const packer = image.createImagePacker(); const path = fixture().path('ocr.png');
      try { await fixture().write(path, new Uint8Array(await packer.packToData(pixel, { format: 'image/png', quality: 100 }))); }
      finally { await pixel.release(); await packer.release(); }
      const text = await OcrService.recognize(path); expect(text.toLowerCase().includes('native')).assertTrue();
    });
    it('systemReminderPublishesIndependentRequestsAndCancelsOnlyTestIds', 0, async (): Promise<void> => {
      if (!await notificationManager.isNotificationEnabled()) { throw new Error('Enable notifications in the isolated UI acceptance flow first'); }
      const tomorrow = new Date(Date.now() + 86400000); const ids: number[] = [];
      try {
        for (let index = 0; index < 2; index++) {
          const request: reminderAgentManager.ReminderRequestCalendar = {
            reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
            dateTime: { year: tomorrow.getFullYear(), month: tomorrow.getMonth() + 1, day: tomorrow.getDate(), hour: 9, minute: index },
            title: 'LumiKit native validation', content: 'Temporary test reminder', notificationId: 909001 + index, ringDuration: 0
          };
          ids.push(await reminderAgentManager.publishReminder(request));
        }
        const active = await reminderAgentManager.getAllValidReminders();
        expect(ids.every((id: number): boolean => active.some((entry: reminderAgentManager.ReminderInfo): boolean => entry.reminderId === id))).assertTrue();
      } finally { for (const id of ids) { await reminderAgentManager.cancelReminder(id); } }
      const remaining = await reminderAgentManager.getAllValidReminders();
      expect(remaining.some((entry: reminderAgentManager.ReminderInfo): boolean => ids.includes(entry.reminderId))).assertFalse();
    });
    it('calendarFallbackCreatesUpdatesDeduplicatesAndRemovesOnlyOwnedEvents', 0, async (): Promise<void> => {
      if (!nextUiContext) { throw new Error('Calendar test requires the granted foreground ability context'); }
      const context = nextUiContext.getHostContext() as common.UIAbilityContext;
      const manager = calendarManager.getCalendarManager(context);
      const name = 'com.lovexjy.LumiKit.test.' + fixture().runId;
      const account = await manager.createCalendar({ name: name, type: calendarManager.CalendarType.LOCAL, displayName: 'LumiKit test' });
      try {
        const unrelated = await account.addEvent({ type: calendarManager.EventType.NORMAL, title: 'Keep this test event',
          startTime: Date.now() + 86400000, endTime: Date.now() + 86500000, identifier: 'test.unmanaged' });
        const event: calendarManager.Event = { type: calendarManager.EventType.NORMAL, title: 'Test warranty', description: 'Camera',
          startTime: Date.now() + 86400000, endTime: Date.now() + 86500000,
          identifier: 'com.lovexjy.LumiKit.inventory.test', reminderTime: [0] };
        await InventoryCalendar.sync(context, [event], name);
        await InventoryCalendar.sync(context, [event], name);
        let events = await account.getEvents(); expect(events.length).assertEqual(2);
        event.title = 'Updated warranty'; event.startTime += 60000; event.endTime += 60000;
        await InventoryCalendar.sync(context, [event], name);
        events = await account.getEvents();
        expect(events.some((entry: calendarManager.Event) => entry.title === 'Updated warranty' &&
          entry.startTime === event.startTime && entry.reminderTime?.[0] === 0)).assertTrue();
        await InventoryCalendar.sync(context, [], name);
        events = await account.getEvents(); expect(events.length).assertEqual(1); expect(events[0].id).assertEqual(unrelated);
      } finally { await manager.deleteCalendar(account); }
    });
    it('pdfCompressionReducesImageDocumentAndKeepsOriginal', 0, async (): Promise<void> => {
      const width = 900; const height = 1200; const bytes = new Uint8Array(width * height * 4); let seed = 17;
      for (let i = 0; i < bytes.length; i += 4) { seed = (seed * 1664525 + 1013904223) >>> 0; bytes[i] = seed & 255; bytes[i + 1] = (seed >>> 8) & 255; bytes[i + 2] = (seed >>> 16) & 255; bytes[i + 3] = 255; }
      const pixel = await image.createPixelMap(bytes.buffer, { size: { width: width, height: height }, pixelFormat: image.PixelMapFormat.RGBA_8888 });
      const packer = image.createImagePacker(); const png = fixture().path('noise.png');
      try { await fixture().write(png, new Uint8Array(await packer.packToData(pixel, { format: 'image/png', quality: 100 }))); }
      finally { await pixel.release(); await packer.release(); }
      const input = fixture().path('scan.pdf'); const source = new pdfService.PdfDocument();
      try { if (!source.createDocument(595, 842)) { throw new Error('Cannot create scan fixture'); } const page = source.getPage(0); try { page.addImageObject(png, 0, 0, 595, 842); } finally { page.release(); } savePDF(source, input, 1); }
      finally { source.releaseDocument(); }
      const output = fixture().path('compressed.pdf'); const before = await fixture().bytes(input);
      const options: ProcessingOptions = { tool: 'pdf-compress', inputs: [input], outputs: [output], pages: '', quality: 60, width: 0, format: '', password: '', targetBytes: 512 * 1024 };
      const task = new taskpool.Task(processFiles, options); task.onReceiveData((_progress: number): void => {});
      await taskpool.execute(task);
      expect(fs.statSync(output).size < before.length).assertTrue();
      const document = openPDF(output, ''); try { expect(document.getPageCount()).assertEqual(1); } finally { document.releaseDocument(); }
      const after = await fixture().bytes(input); expect(after.every((part: number, index: number): boolean => part === before[index])).assertTrue();
    });
  });
}
