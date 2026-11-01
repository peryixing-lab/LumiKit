import { FormField, LocalForm, FieldAnswer, validForm, validFormField, FIELD_TYPES } from './FormModels';
import { validAttachment, newLocalId } from '../inventory/InventoryModels';

export class LumiFormDraft {
  schema: LocalForm = new LocalForm();
  answers: FieldAnswer[] = [];
  field: FormField = new FormField();
  optionsText: string = '';
  mode: string = 'edit';
  savedAt: number = 0;
}
export function validFormDraft(draft: LumiFormDraft): boolean {
  return draft !== null && typeof draft === 'object' && validForm(draft.schema) && validFormField(draft.field) &&
    Array.isArray(draft.answers) && draft.answers.length <= 150 && draft.answers.every((answer: FieldAnswer) =>
      answer !== null && typeof answer.fieldId === 'string' && typeof answer.label === 'string' && typeof answer.type === 'string' &&
      typeof answer.value === 'string' && (answer.type === '' || FIELD_TYPES.includes(answer.type)) && Array.isArray(answer.attachments) && answer.attachments.every(validAttachment)) && ['edit', 'fill', 'field'].includes(draft.mode) &&
    typeof draft.optionsText === 'string' && Number.isFinite(draft.savedAt);
}
export function copyForm(source: LocalForm): LocalForm {
  const result = JSON.parse(JSON.stringify(source)) as LocalForm;
  result.id = newLocalId('form'); result.title = source.title + '（副本）'; result.createdAt = Date.now(); result.updatedAt = Date.now();
  result.fields = result.fields.map((field: FormField) => { field.id = newLocalId('field'); return field; });
  return result;
}
export function formTemplate(kind: number): LocalForm {
  const form = new LocalForm(); form.id = newLocalId('form'); form.createdAt = Date.now(); form.updatedAt = Date.now();
  form.title = ['物品登记表', '日常检查清单', '活动报名表'][kind] || '物品登记表';
  const labels = kind === 1 ? ['检查日期', '检查人', '检查结果', '问题描述', '现场照片'] :
    kind === 2 ? ['姓名', '联系方式', '参加日期', '备注'] : ['物品名称', '分类', '购入日期', '价格', '照片与发票'];
  const types = kind === 1 ? ['date', 'text', 'radio', 'textarea', 'attachment'] :
    kind === 2 ? ['text', 'text', 'date', 'textarea'] : ['text', 'text', 'date', 'number', 'attachment'];
  form.fields = labels.map((label: string, index: number) => {
    const field = new FormField(); field.id = newLocalId('field'); field.label = label; field.type = types[index];
    field.required = index === 0; if (field.type === 'radio') { field.options = ['正常', '需要处理']; } return field;
  });
  return form;
}
