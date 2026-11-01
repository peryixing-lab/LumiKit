import { common } from '@kit.AbilityKit';
import { UIContext, LengthMetricsUnit } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { FileService } from '../../core/FileService';
import { GroupSummary } from '../files/DataEngine';

export class ChartExport {
  static render(title: string, field: string, metric: string, groups: GroupSummary[], chartType: number, summed: boolean): image.PixelMap {
    const data = groups.slice(0, 8);
    const values = data.map((group: GroupSummary) => summed ? group.sum : group.count);
    if (!data.length) { throw new Error('请先生成分组图表'); }
    if (chartType === 3 && (values.some((value: number) => value < 0) || values.reduce((sum: number, value: number) => sum + value, 0) <= 0)) {
      throw new Error('饼图需要非负且总和大于零的数据');
    }
    const surface = new OffscreenCanvas(1200, 900, LengthMetricsUnit.PX);
    const canvas = surface.getContext('2d', new RenderingContextSettings(true));
    const colors: string[] = ['#3978F6', '#6A98FF', '#72C7D4', '#517CAE', '#9AABDE', '#92C0EE', '#A3D7DE', '#C0D1F4'];
    canvas.fillStyle = '#FFFFFF'; canvas.fillRect(0, 0, 1200, 900);
    canvas.fillStyle = '#1D2D43'; canvas.font = 'bold 36px sans-serif'; canvas.fillText(title.slice(0, 30), 60, 72);
    canvas.font = '22px sans-serif'; canvas.fillStyle = '#64748B'; canvas.fillText('按 ' + field + ' 分组 · ' + metric, 60, 120);
    const max = Math.max(1, ...values.map((value: number) => Math.abs(value)));
    canvas.font = '20px sans-serif';
    if (chartType === 3) {
      let angle = -Math.PI / 2; const total = values.reduce((sum: number, value: number) => sum + value, 0);
      for (let i = 0; i < values.length; i++) {
        const next = angle + values[i] / total * Math.PI * 2;
        canvas.beginPath(); canvas.moveTo(430, 405); canvas.arc(430, 405, 210, angle, next); canvas.closePath(); canvas.fillStyle = colors[i]; canvas.fill(); angle = next;
      }
    } else if (chartType === 0) {
      const negative = values.some((value: number) => value < 0); const origin = negative ? 470 : 240; const scale = negative ? 300 : 530;
      for (let i = 0; i < data.length; i++) {
        const y = 190 + i * 55; canvas.fillStyle = '#3A4B68'; canvas.fillText((data[i].label || '（空值）').slice(0, 10), 60, y + 23);
        const length = values[i] / max * scale; canvas.fillStyle = colors[i]; canvas.fillRect(Math.min(origin, origin + length), y, Math.max(1, Math.abs(length)), 30);
      }
    } else {
      const negative = values.some((value: number) => value < 0); const baseline = negative ? 380 : 600; const scale = negative ? 180 : 360;
      canvas.strokeStyle = '#D9E4F2'; canvas.lineWidth = 2; canvas.beginPath(); canvas.moveTo(70, baseline); canvas.lineTo(810, baseline); canvas.stroke();
      if (chartType === 2) {
        canvas.beginPath(); canvas.strokeStyle = '#3978F6'; canvas.lineWidth = 4;
        for (let i = 0; i < data.length; i++) { const x = 90 + (i + 0.5) * 700 / data.length; const y = baseline - values[i] / max * scale; if (i === 0) { canvas.moveTo(x, y); } else { canvas.lineTo(x, y); } }
        canvas.stroke();
      }
      for (let i = 0; i < data.length; i++) {
        const x = 90 + (i + 0.5) * 700 / data.length; const y = baseline - values[i] / max * scale; canvas.fillStyle = colors[i];
        if (chartType === 1) { canvas.fillRect(x - 22, Math.min(y, baseline), 44, Math.max(1, Math.abs(baseline - y))); }
        else { canvas.beginPath(); canvas.arc(x, y, 7, 0, Math.PI * 2); canvas.fill(); }
        canvas.fillStyle = '#64748B'; canvas.textAlign = 'center'; canvas.fillText((data[i].label || '（空值）').slice(0, 5), x, 645);
      }
      canvas.textAlign = 'left';
    }
    for (let i = 0; i < data.length; i++) {
      const y = 210 + i * 60; canvas.fillStyle = colors[i]; canvas.fillRect(860, y - 15, 14, 14);
      canvas.fillStyle = '#1D2D43'; canvas.font = '19px sans-serif'; canvas.fillText((data[i].label || '（空值）').slice(0, 12), 886, y);
      canvas.fillStyle = '#64748B'; canvas.font = '17px sans-serif'; canvas.fillText(Number.isInteger(values[i]) ? values[i].toString() : values[i].toFixed(2), 886, y + 24);
    }
    canvas.fillStyle = '#64748B'; canvas.font = '20px sans-serif';
    canvas.fillText('当前数据 ' + groups.length.toString() + ' 组 · 图中展示前 ' + data.length.toString() + ' 组', 60, 770);
    canvas.font = '18px sans-serif'; canvas.fillText('集萤 LumiKit · ' + new Date().toLocaleString(), 60, 832);
    return canvas.getPixelMap(0, 0, 1200, 900);
  }
  static async create(ctx: common.UIAbilityContext, uiContext: UIContext, title: string, field: string, metric: string,
    groups: GroupSummary[], chartType: number, summed: boolean): Promise<string> {
    let rendered: image.PixelMap | undefined;
    uiContext.runScopedTask(() => { rendered = ChartExport.render(title, field, metric, groups, chartType, summed); });
    if (!rendered) { throw new Error('图表生成失败，请重新打开页面后重试'); }
    const pixel = rendered;
    const packer = image.createImagePacker();
    const name = FileService.cleanName(title) + '_图表.png'; const path = FileService.outputPath(ctx, name);
    try {
      const bytes = await packer.packToData(pixel, { format: 'image/png', quality: 100 });
      const output = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { await fs.write(output.fd, bytes); } finally { await fs.close(output); }
      await FileService.register(ctx, path, name); return path;
    } finally { await pixel.release(); await packer.release(); }
  }
}
