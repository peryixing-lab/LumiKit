import { LumiCollection, LumiFlowRecipe, validCollection, validFlowRecipe } from '../features/workbench/WorkbenchModels';
import { InventoryItem, validInventoryItem } from '../features/inventory/InventoryModels';
import { LocalForm, FormResponse, validForm, validResponse } from '../features/forms/FormModels';
import { LumiFilePreset, validFilePreset } from '../features/files/FilePresets';
import { LumiFormDraft, validFormDraft } from '../features/forms/FormDrafts';
import { ToolRegistry } from './ToolRegistry';
import { LumiMaterialPack, LumiMaterialTemplate, validMaterialPack, validMaterialTemplate } from '../features/materials/MaterialPackModels';

class SavedAnalysis {
  id: string = '';
  name: string = '';
  csv: string = '';
  savedAt: number = 0;
}

function uniqueIds(ids: string[]): boolean {
  return ids.every((id: string) => typeof id === 'string' && id.trim().length > 0) && new Set(ids).size === ids.length;
}

/** Reject malformed domain data before a restore can replace a valid module. */
export function validateBackupDocument(key: string, value: string): boolean {
  switch (key) {
    case 'material.packs': { const packs = JSON.parse(value) as LumiMaterialPack[]; return Array.isArray(packs) && packs.length <= 30 && packs.every(validMaterialPack) && uniqueIds(packs.map((pack: LumiMaterialPack): string => pack.id)); }
    case 'material.templates': { const templates = JSON.parse(value) as LumiMaterialTemplate[]; return Array.isArray(templates) && templates.length <= 30 && templates.every(validMaterialTemplate) && uniqueIds(templates.map((template: LumiMaterialTemplate): string => template.id)); }
    case 'workspace.collections': { const entries = JSON.parse(value) as LumiCollection[]; return Array.isArray(entries) && entries.every(validCollection) && uniqueIds(entries.map((entry: LumiCollection) => entry.id)); }
    case 'workbench.recipes': { const entries = JSON.parse(value) as LumiFlowRecipe[]; return Array.isArray(entries) && entries.length <= 30 && entries.every(validFlowRecipe) && uniqueIds(entries.map((entry: LumiFlowRecipe) => entry.id)); }
    case 'forms.autodraft': { const draft = JSON.parse(value) as LumiFormDraft; return draft === null || validFormDraft(draft); }
    case 'file.presets': { const entries = JSON.parse(value) as LumiFilePreset[]; return Array.isArray(entries) && entries.length <= 30 && entries.every(validFilePreset); }
    case 'favorites': {
      const list = JSON.parse(value) as string[];
      return Array.isArray(list) && list.length <= 26 && list.every((id: string, index: number) =>
        typeof id === 'string' && ToolRegistry.find(id) !== undefined && list.indexOf(id) === index);
    }
    case 'inventory.items': {
      const list = JSON.parse(value) as InventoryItem[];
      return Array.isArray(list) && list.every(validInventoryItem) &&
        uniqueIds(list.map((item: InventoryItem) => item.id)) &&
        list.every((item: InventoryItem) => item.name.trim().length > 0 &&
          uniqueIds(item.attachments.map((attachment) => attachment.id)) &&
          uniqueIds(item.lending.map((loan) => loan.id)));
    }
    case 'forms.schemas': {
      const list = JSON.parse(value) as LocalForm[];
      return Array.isArray(list) && list.every(validForm) && uniqueIds(list.map((form: LocalForm) => form.id)) &&
        list.every((form: LocalForm) => form.title.trim().length > 0 &&
          uniqueIds(form.fields.map((field) => field.id)) &&
          form.fields.every((field) => field.label.trim().length > 0 &&
            (!['select', 'radio', 'checkbox'].includes(field.type) ||
              (field.options.length > 0 && field.options.every((option: string) => option.trim().length > 0) &&
                new Set(field.options).size === field.options.length))));
    }
    case 'forms.responses': {
      const list = JSON.parse(value) as FormResponse[];
      return Array.isArray(list) && list.every(validResponse) && uniqueIds(list.map((response: FormResponse) => response.id)) &&
        list.every((response: FormResponse) => uniqueIds(response.answers.map((answer) => answer.fieldId)));
    }
    case 'analytics-projects': {
      const list = JSON.parse(value) as SavedAnalysis[];
      return Array.isArray(list) && list.length <= 10 && list.every((project: SavedAnalysis) =>
        project !== null && typeof project === 'object' && typeof project.id === 'string' &&
        typeof project.name === 'string' && typeof project.csv === 'string' &&
        typeof project.savedAt === 'number' && Number.isFinite(project.savedAt)) &&
        uniqueIds(list.map((project: SavedAnalysis) => project.id));
    }
    // Legacy metadata exports may include this key. Physical file indices are never restored.
    case 'workspace': return Array.isArray(JSON.parse(value));
    default: return false;
  }
}
