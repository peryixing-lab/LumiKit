import { BusinessError } from '@kit.BasicServicesKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';

export class OcrService {
  static async recognize(path: string): Promise<string> {
    if (!canIUse('SystemCapability.AI.OCR.TextRecognition')) { throw new Error('当前设备不支持系统文字识别'); }
    const source = image.createImageSource(path);
    try {
      if (!await textRecognition.init()) { throw new Error('系统文字识别服务暂不可用，请在支持此能力的真机上重试'); }
      const info = await source.getImageInfo();
      if (info.size.width * info.size.height > 40000000) { throw new Error('图片过大，请先缩小'); }
      const ratio = Math.min(1, 4096 / Math.max(info.size.width, info.size.height));
      const pixel = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: { width: Math.max(1, Math.round(info.size.width * ratio)), height: Math.max(1, Math.round(info.size.height * ratio)) } });
      try {
        const result = await textRecognition.recognizeText({ pixelMap: pixel });
        if (!result.value.trim()) { throw new Error('未识别到文字，请选择更清晰的图片'); }
        return result.value;
      } finally { await pixel.release(); }
    } catch (error) {
      const code = (error as BusinessError).code;
      if (code === 1001400001 || code === 1001400002) { throw new Error('系统文字识别服务异常（' + code.toString() + '），请换一张清晰图片或在真机上重试'); }
      if ((error as Error).message?.toLowerCase().includes('timed out')) {
        throw new Error('系统文字识别服务超时，请稍后重试或在支持此能力的真机上使用');
      }
      throw new Error((error as Error).message || '文字识别未完成');
    } finally { await source.release(); try { await textRecognition.release(); } catch (_) {} }
  }
}
