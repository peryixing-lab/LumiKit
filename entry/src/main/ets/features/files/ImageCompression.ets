import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';

/** Bounded search. Never publish a larger file; keep the original untouched. */
export async function compressImage(input: string, output: string, format: string, quality: number,
  width: number, targetBytes: number): Promise<boolean> {
  if (!['image/jpeg', 'image/webp'].includes(format)) { throw new Error('图片压缩请选择 JPEG 或 WebP'); }
  const source = image.createImageSource(input);
  const packer = image.createImagePacker();
  let saved = false;
  try {
    const info = await source.getImageInfo();
    if (info.size.width * info.size.height > 40000000) { throw new Error('图片超过 4,000 万像素，请先缩小再导入'); }
    if (await source.getFrameCount() > 1) { throw new Error('动态图片暂不支持压缩，请选择静态图片'); }
    const baseWidth = width > 0 ? Math.min(width, info.size.width) : info.size.width;
    let bestSize = fs.statSync(input).size;
    for (let scaleStep = 0; scaleStep < (targetBytes > 0 ? 4 : 1); scaleStep++) {
      if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
      const outWidth = Math.max(1, Math.round(baseWidth * Math.pow(0.75, scaleStep)));
      const pixel = await source.createPixelMap({ desiredSize: {
        width: outWidth, height: Math.max(1, Math.round(info.size.height * outWidth / info.size.width))
      } });
      try {
        for (let qualityStep = 0; qualityStep < (targetBytes > 0 ? 3 : 1); qualityStep++) {
          if (taskpool.Task.isCanceled()) { throw new Error('任务已取消'); }
          const bytes = await packer.packToData(pixel, { format: format, quality: Math.max(1, Math.round(quality) - qualityStep * 20) });
          if (bytes.byteLength < bestSize) {
            const file = fs.openSync(output, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
            try { fs.writeSync(file.fd, bytes); } finally { fs.closeSync(file); }
            bestSize = bytes.byteLength; saved = true;
          }
          if (saved && (!targetBytes || bestSize <= targetBytes)) { return true; }
        }
      } finally { await pixel.release(); }
    }
    return saved;
  } finally { await source.release(); await packer.release(); }
}
