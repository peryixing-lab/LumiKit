export class LumiFilePreset {
  id: string = '';
  name: string = '';
  tool: string = '';
  format: number = 0;
  quality: number = 85;
  width: string = '';
  targetMB: string = '';
}
export function validFilePreset(preset: LumiFilePreset): boolean {
  return preset !== null && typeof preset === 'object' && typeof preset.id === 'string' && typeof preset.name === 'string' &&
    preset.name.length > 0 && preset.name.length <= 40 && ['image-convert', 'image-compress', 'images-pdf', 'pdf-compress'].includes(preset.tool) &&
    Number.isInteger(preset.format) && preset.format >= 0 && preset.format <= 2 && (preset.tool !== 'image-compress' || preset.format > 0) && Number.isFinite(preset.quality) &&
    preset.quality >= 1 && preset.quality <= 100 && typeof preset.width === 'string' &&
    (!preset.width || (Number.isInteger(Number(preset.width)) && Number(preset.width) > 0 && Number(preset.width) <= 8192)) &&
    typeof preset.targetMB === 'string' && (!preset.targetMB || (Number(preset.targetMB) > 0 && Number(preset.targetMB) <= 100));
}
