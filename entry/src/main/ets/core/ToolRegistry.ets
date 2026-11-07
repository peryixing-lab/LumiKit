export class ToolDescriptor {
  id: string = '';
  name: string = '';
  description: string = '';
  category: string = '';
  icon: string = '';
  supportedTypes: string[] = [];
}

export class ToolCategory {
  id: string = '';
  name: string = '';
  caption: string = '';
  icon: string = '';
  count: number = 0;
}

export const CATEGORIES: ToolCategory[] = [
  { id: 'pdf', name: 'PDF 工具箱', caption: '让每一页，各就各位', icon: 'pdf', count: 7 },
  { id: 'convert', name: '格式转换', caption: '换个格式，继续创作', icon: 'convert', count: 6 },
  { id: 'inventory', name: '物品管理', caption: '珍惜拥有，井然有序', icon: 'inventory', count: 1 },
  { id: 'forms', name: '表单生成器', caption: '把想法，变成一张表', icon: 'forms', count: 1 },
  { id: 'developer', name: '开发者工具', caption: '灵感之外，效率之内', icon: 'code', count: 10 },
  { id: 'analytics', name: '数据分析', caption: '从数字里，发现答案', icon: 'chart', count: 1 }
];

export const TOOLS: ToolDescriptor[] = [
  { id: 'pdf-compress', name: 'PDF 压缩', description: '设置目标大小，生成图像压缩副本', category: 'pdf', icon: 'tool-pdf-compress', supportedTypes: ['application/pdf'] },
  { id: 'pdf-edit', name: 'PDF 页面整理', description: '缩略图排序、旋转与删除页面', category: 'pdf', icon: 'tool-pdf-edit', supportedTypes: ['application/pdf'] },
  { id: 'image-ocr', name: '图片文字识别', description: '本机识别、核对与导出图片中的文字', category: 'convert', icon: 'tool-image-ocr', supportedTypes: ['image/*'] },
  { id: 'pdf-merge', name: 'PDF 合并', description: '将多个 PDF 合为一份文档', category: 'pdf', icon: 'tool-pdf-merge', supportedTypes: ['application/pdf'] },
  { id: 'pdf-split', name: 'PDF 拆分', description: '按页拆分，独立保存', category: 'pdf', icon: 'tool-pdf-split', supportedTypes: ['application/pdf'] },
  { id: 'pdf-extract', name: '页面提取', description: '选择并提取指定页面', category: 'pdf', icon: 'tool-pdf-extract', supportedTypes: ['application/pdf'] },
  { id: 'pdf-images', name: 'PDF 转图片', description: '将文档页面导出为图片', category: 'pdf', icon: 'tool-pdf-images', supportedTypes: ['application/pdf'] },
  { id: 'images-pdf', name: '图片转 PDF', description: '将多张图片整理成文档', category: 'pdf', icon: 'tool-images-pdf', supportedTypes: ['image/*'] },
  { id: 'image-compress', name: '图片压缩', description: '批量缩小图片，设置质量、尺寸与目标大小', category: 'convert', icon: 'tool-image-compress', supportedTypes: ['image/*'] },
  { id: 'image-convert', name: '图片转换', description: 'PNG / JPEG / WebP · 尺寸与质量', category: 'convert', icon: 'tool-image-convert', supportedTypes: ['image/*'] },
  { id: 'csv-json', name: 'CSV → JSON', description: '表格数据转为结构化文本', category: 'convert', icon: 'tool-csv-json', supportedTypes: ['text/csv'] },
  { id: 'json-csv', name: 'JSON → CSV', description: '将对象数组导出为表格', category: 'convert', icon: 'tool-json-csv', supportedTypes: ['application/json'] },
  { id: 'text-convert', name: 'TXT ↔ Markdown', description: '纯文本格式转换', category: 'convert', icon: 'tool-text-convert', supportedTypes: ['text/plain','text/markdown'] },
  { id: 'inventory', name: '我的物品', description: '物品、附件、保修与借出记录', category: 'inventory', icon: 'tool-inventory', supportedTypes: [] },
  { id: 'forms', name: '本地表单', description: '设计表单、填写与导出回答', category: 'forms', icon: 'tool-forms', supportedTypes: [] },
  { id: 'json', name: 'JSON 格式化', description: '校验、格式化与压缩', category: 'developer', icon: 'tool-json', supportedTypes: ['application/json'] },
  { id: 'base64', name: 'Base64', description: '文本编码与解码', category: 'developer', icon: 'tool-base64', supportedTypes: ['text/plain'] },
  { id: 'url', name: 'URL 编码', description: '安全编码与解码 URL', category: 'developer', icon: 'tool-url', supportedTypes: ['text/plain'] },
  { id: 'timestamp', name: '时间戳', description: '在日期与时间戳间转换', category: 'developer', icon: 'tool-timestamp', supportedTypes: ['text/plain'] },
  { id: 'hash', name: 'SHA-256 哈希', description: '计算文本的 SHA-256 摘要', category: 'developer', icon: 'tool-hash', supportedTypes: ['text/plain'] },
  { id: 'uuid', name: 'UUID 生成', description: '生成随机的唯一标识符', category: 'developer', icon: 'tool-uuid', supportedTypes: [] },
  { id: 'color', name: '颜色转换', description: 'HEX / RGB / HSL', category: 'developer', icon: 'tool-color', supportedTypes: ['text/plain'] },
  { id: 'diff', name: '文本对比', description: '逐行发现文本差异', category: 'developer', icon: 'tool-diff', supportedTypes: ['text/plain'] },
  { id: 'regex', name: '正则测试', description: '匹配表达式与测试文本', category: 'developer', icon: 'tool-regex', supportedTypes: ['text/plain'] },
  { id: 'markdown', name: 'Markdown 预览', description: '边写边看，专注表达', category: 'developer', icon: 'tool-markdown', supportedTypes: ['text/markdown'] },
  { id: 'analytics', name: '表格数据分析', description: 'CSV / Excel 导入、统计与图表导出', category: 'analytics', icon: 'tool-analytics', supportedTypes: ['text/csv', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'] }
];

class LumiToolSearchAliases {
  toolId: string = '';
  phrases: string[] = [];
}

/** Local scene vocabulary: suggestions still lead to an existing tool. */
const TOOL_SEARCH_ALIASES: LumiToolSearchAliases[] = [
  { toolId: 'image-compress', phrases: ['缩小照片', '缩小图片', '照片太大', '图片太大', '减小图片体积', '压缩照片', '报名', '证件照'] },
  { toolId: 'image-convert', phrases: ['换图片格式', '换照片格式', '照片转格式', '改图片尺寸', '调整照片大小', '报名', '证件照'] },
  { toolId: 'image-ocr', phrases: ['识字', '图片提取文字', '照片提取文字', '截图提取文字', '拍照识字', '截图识字', '票据文字', '发票识别'] },
  { toolId: 'pdf-compress', phrases: ['文档太大', 'PDF太大', '缩小PDF', '减小PDF体积', '提交材料', '报销', '报名'] },
  { toolId: 'pdf-edit', phrases: ['调整页序', '换页顺序', '文档旋转', '删除页面', '整理材料', '提交材料', '报名'] },
  { toolId: 'pdf-merge', phrases: ['合并材料', '合并文档', '拼接PDF', '合成一份', '提交材料', '报销', '报名'] },
  { toolId: 'pdf-split', phrases: ['文档拆开', '一页一份', '拆开材料'] },
  { toolId: 'pdf-extract', phrases: ['取出几页', '保留几页', '只要几页', '抽取页面'] },
  { toolId: 'pdf-images', phrases: ['PDF转照片', 'PDF转截图', '文档转图片'] },
  { toolId: 'images-pdf', phrases: ['照片转PDF', '截图转PDF', '合并截图', '照片合成文档', '合并材料', '报销', '报名'] },
  { toolId: 'inventory', phrases: ['保修', '购买凭证', '发票', '借东西', '借出归还', '登记物品'] },
  { toolId: 'forms', phrases: ['报名表', '登记表', '检查表', '填写表单'] },
  { toolId: 'analytics', phrases: ['统计表格', '统计数据', 'Excel统计', '表格画图', '销售汇总'] }
];

export class ToolRegistry {
  static find(id: string): ToolDescriptor | undefined { return TOOLS.find((tool: ToolDescriptor) => tool.id === id); }
  static search(query: string, category: string = 'all'): ToolDescriptor[] {
    const term = query.trim().toLowerCase().replace(/\s+/g, '');
    return TOOLS.filter((tool: ToolDescriptor) => (category === 'all' || tool.category === category) &&
      (term.length === 0 || `${tool.name} ${tool.description} ${tool.id}`.toLowerCase().replace(/\s+/g, '').includes(term) ||
        TOOL_SEARCH_ALIASES.some((entry: LumiToolSearchAliases): boolean => entry.toolId === tool.id &&
          entry.phrases.some((phrase: string): boolean => phrase.toLowerCase().replace(/\s+/g, '').includes(term)))));
  }
  static forMime(mime: string): ToolDescriptor[] {
    return TOOLS.filter((tool: ToolDescriptor) => tool.supportedTypes.some((type: string) =>
      type === mime || (type.endsWith('/*') && mime.startsWith(type.slice(0, -1)))));
  }
}
