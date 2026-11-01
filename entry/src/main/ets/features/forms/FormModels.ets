import { LocalAttachment, validAttachment } from '../inventory/InventoryModels';

export class FormField {
  id: string = '';
  type: string = 'text';
  label: string = '';
  description: string = '';
  required: boolean = false;
  defaultValue: string = '';
  options: string[] = [];
}

export class LocalForm {
  id: string = '';
  title: string = '';
  description: string = '';
  fields: FormField[] = [];
  createdAt: number = 0;
  updatedAt: number = 0;
}

export class FieldAnswer {
  fieldId: string = '';
  label: string = '';
  type: string = '';
  value: string = '';
  attachments: LocalAttachment[] = [];
}

export class FormResponse {
  id: string = '';
  formId: string = '';
  formTitle: string = '';
  submittedAt: string = '';
  answers: FieldAnswer[] = [];
}

export class JsonFieldSchema {
  type: string = 'string';
  title: string = '';
  description: string = '';
  format?: string;
  enum?: string[];
  minimum?: number;
  maximum?: number;
  default?: string | number | string[];
  items?: JsonFieldSchema;
  uniqueItems?: boolean;
  minLength?: number;
  minItems?: number;
}

export class JsonFormSchema {
  $schema: string = 'https://json-schema.org/draft/2020-12/schema';
  title: string = '';
  description: string = '';
  type: string = 'object';
  properties: Record<string, JsonFieldSchema> = {};
  required: string[] = [];
  additionalProperties: boolean = false;
}

export const FIELD_TYPES: string[] = ['text', 'textarea', 'radio', 'checkbox', 'date', 'number', 'select', 'rating', 'attachment'];
export const FIELD_NAMES: string[] = ['单行文字', '多行文字', '单选', '多选', '日期', '数字', '下拉选择', '评分', '本地附件'];

export function fieldTypeName(type: string): string {
  const index = FIELD_TYPES.indexOf(type);
  return index >= 0 ? FIELD_NAMES[index] : '文字';
}

export function validFormField(field: FormField): boolean {
  return field !== null && typeof field === 'object' && typeof field.id === 'string' && typeof field.label === 'string' &&
    FIELD_TYPES.includes(field.type) && typeof field.required === 'boolean' && typeof field.description === 'string' &&
    typeof field.defaultValue === 'string' && Array.isArray(field.options) &&
    field.options.every((option: string) => typeof option === 'string');
}

export function validForm(form: LocalForm): boolean {
  return form !== null && typeof form === 'object' && typeof form.id === 'string' && typeof form.title === 'string' &&
    typeof form.description === 'string' && Array.isArray(form.fields) && form.fields.every(validFormField);
}

export function validResponse(response: FormResponse): boolean {
  return response !== null && typeof response === 'object' && typeof response.id === 'string' &&
    typeof response.formId === 'string' && typeof response.formTitle === 'string' && typeof response.submittedAt === 'string' &&
    Array.isArray(response.answers) && response.answers.every((answer: FieldAnswer) =>
      answer !== null && typeof answer === 'object' && typeof answer.fieldId === 'string' &&
      typeof answer.label === 'string' && typeof answer.type === 'string' && typeof answer.value === 'string' &&
      Array.isArray(answer.attachments) && answer.attachments.every(validAttachment));
}

export function buildJsonSchema(form: LocalForm): JsonFormSchema {
  const schema = new JsonFormSchema();
  schema.title = form.title;
  schema.description = form.description;
  form.fields.forEach((field: FormField) => {
    const property = new JsonFieldSchema();
    property.title = field.label;
    property.description = field.description;
    if (field.type === 'number' || field.type === 'rating') {
      property.type = field.type === 'rating' ? 'integer' : 'number';
      if (field.type === 'rating') { property.minimum = 1; property.maximum = 5; }
      if (field.defaultValue) { property.default = Number(field.defaultValue); }
    } else if (field.type === 'checkbox' || field.type === 'attachment') {
      property.type = 'array';
      property.items = new JsonFieldSchema();
      if (field.type === 'checkbox') {
        property.items.enum = field.options;
        property.uniqueItems = true;
        if (field.defaultValue) { property.default = field.defaultValue.split('|').filter((value: string) => field.options.includes(value)); }
      }
      if (field.required) { property.minItems = 1; }
    } else {
      if (field.type === 'date') { property.format = 'date'; }
      if (field.type === 'radio' || field.type === 'select') { property.enum = field.options; }
      if (field.defaultValue) { property.default = field.defaultValue; }
      if (field.required) { property.minLength = 1; }
    }
    schema.properties[field.id] = property;
    if (field.required) { schema.required.push(field.id); }
  });
  return schema;
}

export function csvCell(value: string): string {
  // Neutralize spreadsheet formulas while preserving the displayed answer.
  const safe = /^[=+@\-\t\r]/.test(value) ? `'${value}` : value;
  return `"${safe.replace(/"/g, '""')}"`;
}

export function responseCsv(form: LocalForm, responses: FormResponse[]): string {
  const columns: FormField[] = form.fields.slice();
  responses.forEach((response: FormResponse) => {
    response.answers.forEach((answer: FieldAnswer) => {
      if (!columns.some((field: FormField) => field.id === answer.fieldId)) {
        const old = new FormField();
        old.id = answer.fieldId;
        old.label = `${answer.label}（历史字段）`;
        columns.push(old);
      }
    });
  });
  const rows: string[] = [['提交时间'].concat(columns.map((field: FormField) => field.label)).map(csvCell).join(',')];
  responses.forEach((response: FormResponse) => {
    const values: string[] = [response.submittedAt];
    columns.forEach((field: FormField) => {
      const answer = response.answers.find((entry: FieldAnswer) => entry.fieldId === field.id);
      values.push(answer ? (answer.type === 'attachment' ? answer.attachments.map((attachment: LocalAttachment) => attachment.name).join(' | ') : answer.value) : '');
    });
    rows.push(values.map(csvCell).join(','));
  });
  return '\uFEFF' + rows.join('\r\n');
}
