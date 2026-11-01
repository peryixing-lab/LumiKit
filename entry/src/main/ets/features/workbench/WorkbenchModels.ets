export class LumiCollection {
  id: string = '';
  name: string = '';
  createdAt: number = 0;
}
export class LumiFlowRecipe {
  id: string = '';
  name: string = '';
  kind: string = 'materials';
  targetMB: string = '5';
  quality: number = 85;
  outputName: string = '提交材料';
}
export class LumiFileSession {
  toolId: string = '';
  paths: string[] = [];
  name: string = '';
  pages: string = '';
  quality: number = 90;
  format: number = 0;
  targetWidth: string = '';
  targetMB: string = '';
  updatedAt: number = 0;
  edits: LumiSavedPage[] = [];
}
export class LumiSavedPage {
  original: number = 0;
  rotation: number = 0;
}
export class LumiFlowSession {
  id: string = '';
  kind: string = 'materials';
  name: string = '提交材料';
  inputs: string[] = [];
  prepared: string[] = [];
  basePath: string = '';
  organizedPath: string = '';
  finalPath: string = '';
  edits: LumiSavedPage[] = [];
  targetMB: string = '5';
  quality: number = 85;
  stage: number = 0;
  updatedAt: number = 0;
  error: string = '';
}
export function validFlowRecipe(recipe: LumiFlowRecipe): boolean {
  return !!recipe && typeof recipe.id === 'string' && !!recipe.id && typeof recipe.name === 'string' &&
    recipe.name.trim().length > 0 && recipe.name.length <= 40 && ['materials', 'screenshots'].includes(recipe.kind) &&
    typeof recipe.targetMB === 'string' && (!recipe.targetMB || (Number.isFinite(Number(recipe.targetMB)) && Number(recipe.targetMB) > 0 && Number(recipe.targetMB) <= 100)) &&
    Number.isInteger(recipe.quality) && recipe.quality >= 1 && recipe.quality <= 100 &&
    typeof recipe.outputName === 'string' && recipe.outputName.trim().length > 0 && recipe.outputName.length <= 80;
}
export function validCollection(entry: LumiCollection): boolean {
  return !!entry && typeof entry.id === 'string' && entry.id.length > 0 && typeof entry.name === 'string' &&
    entry.name.trim().length > 0 && entry.name.length <= 80 && Number.isFinite(entry.createdAt);
}
export function validFileSession(entry: LumiFileSession): boolean {
  return !!entry && typeof entry.toolId === 'string' && Array.isArray(entry.paths) && entry.paths.length <= 20 &&
    entry.paths.every((path: string) => typeof path === 'string') && typeof entry.name === 'string' &&
    typeof entry.pages === 'string' && Number.isFinite(entry.updatedAt) && Number.isFinite(entry.quality) &&
    entry.quality >= 1 && entry.quality <= 100 && [0, 1, 2].includes(entry.format) &&
    typeof entry.targetWidth === 'string' && typeof entry.targetMB === 'string' && validSavedPages(entry.edits);
}
export function validSavedPages(pages: LumiSavedPage[]): boolean {
  return Array.isArray(pages) && pages.length <= 200 && pages.every((page: LumiSavedPage) => !!page &&
    Number.isInteger(page.original) && page.original >= 0 && page.original < 200 && [0, 90, 180, 270].includes(page.rotation)) &&
    new Set(pages.map((page: LumiSavedPage) => page.original)).size === pages.length;
}
export function validFlowSession(flow: LumiFlowSession): boolean {
  return !!flow && typeof flow.id === 'string' && !!flow.id && ['materials', 'screenshots'].includes(flow.kind) &&
    typeof flow.name === 'string' && flow.name.length <= 80 && Number.isInteger(flow.stage) && flow.stage >= 0 && flow.stage <= 3 &&
    Array.isArray(flow.inputs) && flow.inputs.length <= 20 && flow.inputs.every((path: string) => typeof path === 'string') &&
    Array.isArray(flow.prepared) && flow.prepared.length <= flow.inputs.length && flow.prepared.every((path: string) => typeof path === 'string') &&
    typeof flow.basePath === 'string' && typeof flow.organizedPath === 'string' && typeof flow.finalPath === 'string' &&
    typeof flow.targetMB === 'string' && Number.isFinite(flow.quality) && flow.quality >= 1 && flow.quality <= 100 &&
    validSavedPages(flow.edits) && Number.isFinite(flow.updatedAt) && typeof flow.error === 'string';
}
