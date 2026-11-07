import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { DataTable, GroupSummary, NumericSummary } from '../features/files/DataEngine';
import { FieldAnswer, FormField, FormResponse, fieldTypeName, LocalForm } from '../features/forms/FormModels';
import { InventoryItem, LendingRecord, LocalAttachment, localDate } from '../features/inventory/InventoryModels';
import { FileService } from './FileService';
import { StorageService } from './StorageService';

/**
 * Phase 2 Ecosystem Bridge for LumiKit (集萤):
 * Connects LumiKit's OCR, Analytics, Inventory, and Local Forms with
 * LexiNote (知萤 Markdown knowledge base) and LexiGlow (词萤 English companion reader).
 */
export class EcosystemBridge {
  static yamlString(raw: string): string {
    return JSON.stringify((raw || '').replace(/[\r\n\u0000-\u001f]+/g, ' ').trim());
  }

  static escapeTableCell(raw: string): string {
    return (raw || '')
      .replace(/\r?\n/g, ' ')
      .replace(/\|/g, '｜')
      .trim();
  }

  static sanitizeMarkdownFileName(rawTitle: string, fallback: string = '集萤导出笔记'): string {
    const cleaned = FileService.cleanName((rawTitle || '').replace(/\.(md|markdown|txt|csv|xlsx)$/i, '').trim());
    return `${(cleaned || fallback).slice(0, 80)}.md`;
  }

  static resolveShareUtd(fileName: string): string {
    const lower = (fileName || '').toLowerCase();
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      try {
        const resolved = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension('.md');
        if (resolved && resolved.trim().length > 0) {
          return resolved;
        }
      } catch (_) {}
      return 'general.markdown';
    }
    if (lower.endsWith('.txt')) {
      return 'general.plain-text';
    }
    try {
      const dotIdx = lower.lastIndexOf('.');
      if (dotIdx >= 0) {
        const ext = lower.slice(dotIdx);
        const resolved = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(ext);
        if (resolved && resolved.trim().length > 0) {
          return resolved;
        }
      }
    } catch (_) {}
    return uniformTypeDescriptor.UniformDataType.FILE;
  }

  static extractEnglishKeywords(text: string, maxCount: number = 8): string[] {
    const matches = (text || '').slice(0, 8192).match(/[A-Za-z]{4,24}/g) || [];
    const stopWords: string[] = [
      'this', 'that', 'with', 'from', 'have', 'will', 'your', 'they',
      'their', 'what', 'when', 'where', 'which', 'there', 'about', 'would',
      'could', 'should', 'these', 'those', 'into', 'more', 'some', 'such',
      'than', 'then', 'them', 'were', 'been', 'being', 'only', 'also', 'over'
    ];
    const result: string[] = [];
    for (const token of matches) {
      const lower = token.toLowerCase();
      if (stopWords.indexOf(lower) >= 0) {
        continue;
      }
      if (result.indexOf(lower) < 0) {
        result.push(lower);
      }
      if (result.length >= maxCount) {
        break;
      }
    }
    return result;
  }

  static buildOcrNoteMarkdown(
    title: string,
    ocrText: string,
    sourceFileName: string = '',
    dateStr: string = localDate(new Date())
  ): string {
    const cleanTitle = (title || sourceFileName || 'OCR 文字识别摘录')
      .replace(/\.[^.]+$/, '')
      .trim() || 'OCR 文字识别摘录';
    const body = (ocrText || '').replace(/\r\n?/g, '\n').trim();
    const keywords = EcosystemBridge.extractEnglishKeywords(body, 8);
    const lines: string[] = [
      '---',
      `title: ${EcosystemBridge.yamlString(cleanTitle)}`,
      'notebook: "资料摘录"',
      'tags: ["集萤OCR", "文字识别"]',
      'source_app: "LumiKit"',
      'source_uri: "lumikit://tool?id=image-ocr"',
      `source_file: ${EcosystemBridge.yamlString(sourceFileName || cleanTitle)}`,
      `captured_date: ${EcosystemBridge.yamlString(dateStr)}`,
      '---',
      '## 识别正文',
      '',
      body || '（暂无识别文本）'
    ];
    if (keywords.length > 0) {
      const linkedWords = keywords.map((word: string): string =>
        `[[${word}]]（[词萤查词](lexiglow://word?spelling=${encodeURIComponent(word)})）`
      );
      lines.push(
        '',
        '## 英文词汇双链与精读',
        '',
        `- **识别到的核心词汇**：${linkedWords.join(' · ')}`,
        '- **伴读建议**：可将本笔记分享至「词萤」开启全文点词伴读。'
      );
    }
    lines.push(
      '',
      '---',
      `- **来源工具**：[在集萤中打开图片文字识别](lumikit://tool?id=image-ocr)${sourceFileName ? `（原文件：\`${sourceFileName}\`）` : ''}`
    );
    return lines.join('\n') + '\n';
  }

  private static formatStatNumber(value: number): string {
    if (!Number.isFinite(value)) {
      return '0';
    }
    return Number.isInteger(value) ? value.toString() : value.toFixed(2);
  }

  static buildAnalyticsReportMarkdown(
    sourceName: string,
    table: DataTable,
    fieldIndex: number,
    numericIndex: number,
    stats: NumericSummary,
    groups: GroupSummary[],
    dateStr: string = localDate(new Date())
  ): string {
    const cleanTitle = (sourceName || '未命名分析').replace(/\.(csv|xlsx)$/i, '').trim() || '未命名分析';
    const groupHeader = table.headers[fieldIndex] || '默认分组';
    const numericHeader = table.headers[numericIndex] || '数值列';
    const emptyCells = table.rows.reduce(
      (sum: number, row: string[]): number => sum + row.filter((val: string): boolean => val.trim() === '').length,
      0
    );
    const reportTitle = `数据分析报告 · ${cleanTitle}`;
    const lines: string[] = [
      '---',
      `title: ${EcosystemBridge.yamlString(reportTitle)}`,
      'notebook: "数据报告"',
      'tags: ["集萤分析", "数据报告"]',
      'source_app: "LumiKit"',
      'source_uri: "lumikit://tool?id=analytics"',
      `dataset: ${EcosystemBridge.yamlString(cleanTitle)}`,
      `row_count: ${EcosystemBridge.yamlString(String(table.rows.length))}`,
      `column_count: ${EcosystemBridge.yamlString(String(table.headers.length))}`,
      `group_field: ${EcosystemBridge.yamlString(groupHeader)}`,
      `numeric_field: ${EcosystemBridge.yamlString(numericHeader)}`,
      `report_date: ${EcosystemBridge.yamlString(dateStr)}`,
      '---',
      '## 01 数据概览',
      '',
      `- **数据规模**：共 **${table.rows.length}** 行 · **${table.headers.length}** 列（空单元格 ${emptyCells} 个）`,
      `- **分组维度**：\`${groupHeader}\`（共 ${groups.length} 组）`,
      `- **统计指标列**：\`${numericHeader}\``,
      '',
      '## 02 数值统计摘要',
      '',
      '| 统计字段 | 有效数值 | 空值数 | 求和 | 平均值 | 最小值 | 最大值 |',
      '| :--- | :---: | :---: | :---: | :---: | :---: | :---: |',
      `| ${EcosystemBridge.escapeTableCell(numericHeader)} | ${stats.count} | ${stats.empty} | ${EcosystemBridge.formatStatNumber(stats.sum)} | ${stats.count > 0 ? EcosystemBridge.formatStatNumber(stats.mean) : '—'} | ${stats.count > 0 ? EcosystemBridge.formatStatNumber(stats.min) : '—'} | ${stats.count > 0 ? EcosystemBridge.formatStatNumber(stats.max) : '—'} |`
    ];

    if (groups.length > 0) {
      const totalRows = Math.max(1, table.rows.length);
      lines.push(
        '',
        `## 03 按「${groupHeader}」分组汇总`,
        '',
        `| ${EcosystemBridge.escapeTableCell(groupHeader)} | 记录数 | 占总行数比 | ${EcosystemBridge.escapeTableCell(numericHeader)}合计 |`,
        '| :--- | :---: | :---: | :---: |'
      );
      for (const group of groups.slice(0, 30)) {
        const label = EcosystemBridge.escapeTableCell(group.label || '（空值）');
        const ratio = `${((group.count / totalRows) * 100).toFixed(1)}%`;
        lines.push(`| ${label} | ${group.count} | ${ratio} | ${EcosystemBridge.formatStatNumber(group.sum)} |`);
      }
    }

    if (table.headers.length > 0 && table.rows.length > 0) {
      const previewCols = Math.min(8, table.headers.length);
      const headerRow = table.headers.slice(0, previewCols).map((h: string): string => EcosystemBridge.escapeTableCell(h) || '列');
      const dividerRow = headerRow.map((): string => ':---');
      lines.push(
        '',
        `## 04 数据样本预览（前 ${Math.min(15, table.rows.length)} 行）`,
        '',
        `| ${headerRow.join(' | ')} |`,
        `| ${dividerRow.join(' | ')} |`
      );
      for (const row of table.rows.slice(0, 15)) {
        const cells: string[] = [];
        for (let c = 0; c < previewCols; c++) {
          cells.push(EcosystemBridge.escapeTableCell(row[c] || '') || '—');
        }
        lines.push(`| ${cells.join(' | ')} |`);
      }
    }

    lines.push(
      '',
      '---',
      '- **集萤联动**：[在集萤中打开本地数据分析](lumikit://tool?id=analytics)'
    );
    return lines.join('\n') + '\n';
  }

  static buildInventoryMarkdown(
    item: InventoryItem,
    warrantyHint: string = '',
    dateStr: string = localDate(new Date())
  ): string {
    const cleanName = (item.name || '未命名物品').trim() || '未命名物品';
    const categoryTag = (item.category || '未分类').trim() || '未分类';
    const itemUri = `lumikit://inventory?itemId=${encodeURIComponent(item.id || 'item')}`;
    const activeLoan = item.lending.find((loan: LendingRecord): boolean => loan.returnedAt.length === 0);
    const statusText = item.archived
      ? '已归档'
      : activeLoan
        ? `已借给 ${activeLoan.borrower}（预计归还：${activeLoan.dueDate || '未设置'}）`
        : '在用';

    const lines: string[] = [
      '---',
      `title: ${EcosystemBridge.yamlString(cleanName)}`,
      'notebook: "物品档案"',
      `tags: ["集萤物品", ${EcosystemBridge.yamlString(categoryTag)}]`,
      'source_app: "LumiKit"',
      `source_uri: ${EcosystemBridge.yamlString(itemUri)}`,
      `item_id: ${EcosystemBridge.yamlString(item.id)}`,
      `category: ${EcosystemBridge.yamlString(categoryTag)}`,
      `brand: ${EcosystemBridge.yamlString(item.brand)}`,
      `model: ${EcosystemBridge.yamlString(item.model)}`,
      `purchase_date: ${EcosystemBridge.yamlString(item.purchaseDate)}`,
      `warranty_date: ${EcosystemBridge.yamlString(item.warrantyDate)}`,
      `price: ${EcosystemBridge.yamlString(item.price)}`,
      `archived_date: ${EcosystemBridge.yamlString(dateStr)}`,
      '---',
      '## 物品核心档案',
      '',
      '| 属性 | 内容 |',
      '| :--- | :--- |',
      `| **分类** | ${EcosystemBridge.escapeTableCell(categoryTag)} |`,
      `| **品牌 / 型号** | ${EcosystemBridge.escapeTableCell(`${item.brand} ${item.model}`.trim() || '未填写')} |`,
      `| **当前状态** | ${EcosystemBridge.escapeTableCell(statusText)} |`,
      `| **购买日期** | ${EcosystemBridge.escapeTableCell(item.purchaseDate || '未填写')} |`,
      `| **购买价格** | ${item.price ? `¥ ${EcosystemBridge.escapeTableCell(item.price)}` : '未填写'} |`,
      `| **保修截止** | ${EcosystemBridge.escapeTableCell(item.warrantyDate ? `${item.warrantyDate}${warrantyHint ? `（${warrantyHint}）` : ''}` : '未填写')} |`,
      `| **购买渠道** | ${EcosystemBridge.escapeTableCell(item.channel || '未填写')} |`
    ];

    if (item.notes && item.notes.trim()) {
      lines.push('', '## 使用心得与说明书备注', '', item.notes.trim());
    }

    if (item.lending && item.lending.length > 0) {
      lines.push('', '## 借出与归还记录', '');
      for (const loan of item.lending) {
        const state = loan.returnedAt
          ? `${loan.lentAt} 借出 → ${loan.returnedAt} 已归还`
          : `${loan.lentAt} 借出 · 尚未归还（预计：${loan.dueDate || '未设置'}）`;
        lines.push(`- **${loan.borrower}**：${state}`);
      }
    }

    if (item.attachments && item.attachments.length > 0) {
      lines.push('', '## 本地附件清单', '');
      for (const att of item.attachments) {
        lines.push(`- \`${att.name}\`（${Math.ceil(att.size / 1024)} KB）`);
      }
    }

    lines.push(
      '',
      '---',
      `- **集萤联动**：[在集萤中打开「${cleanName}」物品档案](${itemUri})`
    );
    return lines.join('\n') + '\n';
  }

  static buildFormResponseMarkdown(form: LocalForm, response: FormResponse): string {
    const title = (form.title || response.formTitle || '未命名表单').trim();
    const noteTitle = `${title} · 回答记录`;
    const lines: string[] = [
      '---',
      `title: ${EcosystemBridge.yamlString(noteTitle)}`,
      'notebook: "表单归档"',
      `tags: ["集萤表单", ${EcosystemBridge.yamlString(title)}]`,
      'source_app: "LumiKit"',
      'source_uri: "lumikit://tool?id=forms"',
      `form_id: ${EcosystemBridge.yamlString(form.id)}`,
      `response_id: ${EcosystemBridge.yamlString(response.id)}`,
      `submitted_at: ${EcosystemBridge.yamlString(response.submittedAt)}`,
      '---',
      `- **提交时间**：${response.submittedAt}`,
      '',
      '| 字段 | 填写内容 |',
      '| :--- | :--- |'
    ];
    for (const ans of response.answers) {
      const valueText = ans.type === 'attachment'
        ? (ans.attachments.length > 0
          ? ans.attachments.map((a: LocalAttachment): string => a.name).join('、')
          : '无附件')
        : (ans.value || '未填写');
      lines.push(`| **${EcosystemBridge.escapeTableCell(ans.label)}** | ${EcosystemBridge.escapeTableCell(valueText)} |`);
    }
    lines.push(
      '',
      '---',
      '- **集萤联动**：[在集萤中打开本地表单](lumikit://tool?id=forms)'
    );
    return lines.join('\n') + '\n';
  }

  static buildFormSummaryMarkdown(
    form: LocalForm,
    responses: FormResponse[],
    dateStr: string = localDate(new Date())
  ): string {
    const title = (form.title || '未命名表单').trim();
    const noteTitle = `${title} · 收集汇总报告`;
    const lines: string[] = [
      '---',
      `title: ${EcosystemBridge.yamlString(noteTitle)}`,
      'notebook: "表单归档"',
      `tags: ["集萤表单", "表单汇总", ${EcosystemBridge.yamlString(title)}]`,
      'source_app: "LumiKit"',
      'source_uri: "lumikit://tool?id=forms"',
      `form_id: ${EcosystemBridge.yamlString(form.id)}`,
      `response_count: ${EcosystemBridge.yamlString(String(responses.length))}`,
      `exported_date: ${EcosystemBridge.yamlString(dateStr)}`,
      '---'
    ];
    if (form.description && form.description.trim()) {
      lines.push(`> ${form.description.trim()}`, '');
    }
    lines.push(
      `- **字段数量**：${form.fields.length} 个`,
      `- **已收集回答**：${responses.length} 份`,
      '',
      '## 字段结构',
      ''
    );
    for (let i = 0; i < form.fields.length; i++) {
      const f: FormField = form.fields[i];
      lines.push(`${i + 1}. **${f.label}**（${fieldTypeName(f.type)}${f.required ? ' · 必填' : ''}）`);
    }

    if (responses.length > 0 && form.fields.length > 0) {
      const cols = form.fields.slice(0, 8);
      const headers = ['提交时间'].concat(cols.map((f: FormField): string => EcosystemBridge.escapeTableCell(f.label)));
      const dividers = headers.map((): string => ':---');
      lines.push(
        '',
        `## 回答明细表（前 ${Math.min(30, responses.length)} 份）`,
        '',
        `| ${headers.join(' | ')} |`,
        `| ${dividers.join(' | ')} |`
      );
      for (const resp of responses.slice(0, 30)) {
        const rowCells: string[] = [EcosystemBridge.escapeTableCell(resp.submittedAt)];
        for (const col of cols) {
          const matched = resp.answers.find((a: FieldAnswer): boolean => a.fieldId === col.id || a.label === col.label);
          if (!matched) {
            rowCells.push('—');
          } else if (matched.type === 'attachment') {
            rowCells.push(EcosystemBridge.escapeTableCell(matched.attachments.map((a: LocalAttachment): string => a.name).join('、') || '—'));
          } else {
            rowCells.push(EcosystemBridge.escapeTableCell(matched.value || '—'));
          }
        }
        lines.push(`| ${rowCells.join(' | ')} |`);
      }
    }

    lines.push(
      '',
      '---',
      '- **集萤联动**：[在集萤中打开本地表单](lumikit://tool?id=forms)'
    );
    return lines.join('\n') + '\n';
  }

  static extractFrontmatterTitle(markdownContent: string, fallbackTitle: string): string {
    const normalized = (markdownContent || '').replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
    if (normalized.startsWith('---\n')) {
      const lines = normalized.split('\n');
      for (let i = 1; i < lines.length; i++) {
        const trimmed = lines[i].trim();
        if (trimmed === '---' || trimmed === '...') {
          break;
        }
        const match = /^title:\s*(.+)$/i.exec(trimmed);
        if (match) {
          const rawVal = match[1].trim();
          if (rawVal.startsWith('"') && rawVal.endsWith('"')) {
            try {
              return (JSON.parse(rawVal) as string).trim();
            } catch (_) {}
          }
          return rawVal.replace(/^['"]|['"]$/g, '').trim();
        }
      }
    }
    return (fallbackTitle || '集萤导出笔记').replace(/\.(md|markdown|txt|csv|xlsx)$/i, '').trim() || '集萤导出笔记';
  }

  static async shareMarkdownToLexiNote(
    ctx: common.UIAbilityContext,
    title: string,
    markdown: string,
    historyToolId: string = 'ecosystem-share',
    historyLabel: string = '联动导出到知萤'
  ): Promise<string> {
    const normalized = (markdown || '').replace(/\r\n?/g, '\n');
    const content = normalized.endsWith('\n') ? normalized : `${normalized}\n`;
    const cleanTitle = EcosystemBridge.extractFrontmatterTitle(content, title);
    const fileName = EcosystemBridge.sanitizeMarkdownFileName(cleanTitle);
    const path = await FileService.writeText(ctx, fileName, content);
    await StorageService.addHistory(historyToolId, historyLabel, fileName, path);

    const encodedTitle = encodeURIComponent(cleanTitle);
    const encodedContent = encodeURIComponent(content);
    const importUri = encodedContent.length <= 3200
      ? `lexinote://import?source=LumiKit&workspace=${encodeURIComponent('集萤')}&title=${encodedTitle}&content=${encodedContent}`
      : `lexinote://import?source=LumiKit&workspace=${encodeURIComponent('集萤')}&title=${encodedTitle}`;
    const wantParams: Record<string, Object> = {
      'lexinoteMarkdownTitle': cleanTitle,
      'lexinoteMarkdownContent': content,
      'lexinoteSourceApp': 'LumiKit',
      'lexinoteWorkspaceName': '集萤'
    };
    try {
      await ctx.startAbility({
        bundleName: 'com.lovexjy.lexinote',
        abilityName: 'EntryAbility',
        uri: importUri,
        parameters: wantParams
      });
      return path;
    } catch (_) {
      try {
        await ctx.startAbility({
          action: 'ohos.want.action.viewData',
          entities: ['entity.system.browsable'],
          uri: importUri,
          parameters: wantParams
        });
        return path;
      } catch (_) {}
    }

    const record: systemShare.SharedRecord = {
      utd: EcosystemBridge.resolveShareUtd(fileName),
      uri: fileUri.getUriFromPath(path),
      title: fileName,
      label: 'FILE',
      description: '集萤 LumiKit · 沉淀到知萤双链笔记 / 词萤伴读'
    };
    const data = new systemShare.SharedData(record);
    await new systemShare.ShareController(data).show(ctx, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.SINGLE
    });
    return path;
  }

  static async openInLexiGlow(
    ctx: common.UIAbilityContext,
    title: string,
    text: string,
    asArticle: boolean = true
  ): Promise<void> {
    const trimmed = (text || '').trim();
    if (!trimmed) {
      throw new Error('没有可发送的英文内容');
    }
    try {
      const params: Record<string, Object> = asArticle
        ? {
            'route': 'sharedArticle',
            'lexiglowSharedTitle': (title || '集萤 OCR 伴读').slice(0, 80),
            'lexiglowSharedArticle': trimmed.slice(0, 60000)
          }
        : {
            'route': 'shared',
            'lexiglowSharedText': trimmed.slice(0, 4096)
          };
      await ctx.startAbility({
        bundleName: 'com.lovexjy.lexiglow',
        abilityName: 'EntryAbility',
        parameters: params
      });
    } catch (_) {
      await EcosystemBridge.shareMarkdownToLexiNote(
        ctx,
        title || '集萤OCR英文摘录',
        EcosystemBridge.buildOcrNoteMarkdown(title || '集萤OCR英文摘录', trimmed),
        'image-ocr',
        '发送识别文本到词萤'
      );
    }
  }

  static async openNoteInLexiNote(
    ctx: common.UIAbilityContext,
    title: string,
    notebook: string = ''
  ): Promise<void> {
    const cleanTitle = (title || '').trim();
    if (!cleanTitle) {
      return;
    }
    const uri = `lexinote://open?title=${encodeURIComponent(cleanTitle)}${notebook ? `&notebook=${encodeURIComponent(notebook)}` : ''}`;
    try {
      await ctx.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: uri
      });
    } catch (_) {
      await ctx.startAbility({
        action: 'ohos.want.action.viewData',
        uri: uri
      });
    }
  }
}
