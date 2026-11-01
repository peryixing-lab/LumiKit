import { FieldAnswer, fieldTypeName, FormField, FormResponse, LocalForm } from './FormModels';
import { LocalAttachment } from '../inventory/InventoryModels';

export class FormPrintLine {
  text: string = '';
  size: number = 11;
  bold: boolean = false;
  muted: boolean = false;
  gap: number = 0;
}

export type FormTextMeasure = (text: string, size: number, bold: boolean) => number;

/** Wrap by measured font width, retaining explicit paragraph breaks and Unicode code points. */
export function wrapPrintText(text: string, width: number, size: number, bold: boolean,
  measure: FormTextMeasure): string[] {
  const result: string[] = [];
  text.replace(/\r\n?/g, '\n').split('\n').forEach((paragraph: string) => {
    let line = '';
    for (const character of paragraph) {
      if (line && measure(line + character, size, bold) > width) { result.push(line); line = ''; }
      line += character;
    }
    result.push(line);
  });
  return result;
}

export function formPrintLines(form: LocalForm, response: FormResponse | undefined,
  measure: FormTextMeasure): FormPrintLine[] {
  if ((response ? response.answers.length : form.fields.length) > 150) {
    throw new Error('PDF 导出支持最多 150 个字段，请拆分表单后重试');
  }
  const lines: FormPrintLine[] = [];
  let characters = 0;
  const append = (text: string, size: number = 11, bold: boolean = false, muted: boolean = false,
    gap: number = 0): void => {
    characters += text.length;
    if (characters > 30000) { throw new Error('PDF 文字超过 3 万字，请使用 JSON 或 CSV 导出'); }
    const wrapped = wrapPrintText(text, 507, size, bold, measure);
    wrapped.forEach((text: string, index: number) => {
      const line = new FormPrintLine();
      line.text = text;
      line.size = size;
      line.bold = bold;
      line.muted = muted;
      line.gap = index === wrapped.length - 1 ? gap : 0;
      lines.push(line);
    });
  };
  append(response ? response.formTitle : form.title, 23, true, false, 12);
  if (form.description && !response) { append(form.description, 11, false, true, 12); }
  append(response ? `提交时间：${response.submittedAt}` : '本地表单 · 空白填写模板    * 为必填项', 10, false, true, 20);
  if (response) {
    response.answers.forEach((answer: FieldAnswer, index: number) => {
      append(`${index + 1}. ${answer.label}`, 12, true, false, 6);
      append(answer.type === 'attachment' ? (answer.attachments.map((attachment: LocalAttachment) => attachment.name).join('\n') || '未填写') :
        (answer.value || '未填写'), 11, false, false, 18);
    });
    append('附件以文件名列出，原文件请在集萤中单独导出。', 9, false, true);
  } else {
    form.fields.forEach((field: FormField, index: number) => {
      append(`${index + 1}. ${field.label}${field.required ? ' *' : ''}  ·  ${fieldTypeName(field.type)}`, 12, true, false, 6);
      if (field.description) { append(field.description, 10, false, true, 6); }
      if (['radio', 'checkbox', 'select'].includes(field.type)) {
        field.options.forEach((option: string) => append(`${field.type === 'radio' ? '( )' : '[ ]'} ${option}`, 11, false, false, 4));
      } else if (field.type === 'rating') { append('( ) 1    ( ) 2    ( ) 3    ( ) 4    ( ) 5', 11, false, false, 6); }
      else if (field.type === 'date') { append('________ 年 ______ 月 ______ 日', 11, false, false, 6); }
      else if (field.type === 'attachment') { append('附件名称：________________________________________________', 11, false, false, 6); }
      else {
        append('________________________________________________________', 11, false, false, 6);
        if (field.type === 'textarea') {
          append('________________________________________________________', 11, false, false, 6);
          append('________________________________________________________', 11, false, false, 6);
        }
      }
      append('', 5, false, false, 12);
    });
  }
  return lines;
}

export function paginatePrintLines(lines: FormPrintLine[]): FormPrintLine[][] {
  const pages: FormPrintLine[][] = [];
  let page: FormPrintLine[] = [];
  let height = 0;
  for (const line of lines) {
    const lineHeight = line.size * 1.6 + line.gap;
    if (page.length > 0 && height + lineHeight > 720) { pages.push(page); page = []; height = 0; }
    page.push(line);
    height += lineHeight;
  }
  if (page.length > 0 || pages.length === 0) { pages.push(page); }
  return pages;
}
