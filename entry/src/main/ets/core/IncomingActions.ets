import { WorkspaceFile } from './FileService';

export class LumiIncomingAction {
  title: string = '';
  toolId: string = '';
}

/** Catalog order is newest-first; preserve the sender's page order instead. */
export function lumiIncomingFiles(paths: string[], workspace: WorkspaceFile[]): WorkspaceFile[] {
  const files: WorkspaceFile[] = [];
  for (const path of paths) {
    const file = workspace.find((entry: WorkspaceFile): boolean => entry.path === path && !entry.trashedAt);
    if (file && !files.some((entry: WorkspaceFile): boolean => entry.path === path)) { files.push(file); }
  }
  return files;
}

/** Offer an explicit purpose after import; files remain in the workspace on dismissal. */
export function lumiIncomingActions(files: WorkspaceFile[]): LumiIncomingAction[] {
  if (!files.length) { return []; }
  if (files.every((file: WorkspaceFile): boolean => file.mime.startsWith('image/'))) {
    const actions: LumiIncomingAction[] = [{ title: '压缩图片', toolId: 'image-compress' },
      { title: '整理成 PDF', toolId: 'images-pdf' }];
    if (files.length === 1) { actions.push({ title: '识别文字', toolId: 'image-ocr' }); }
    actions.push({ title: '保存在工作区', toolId: 'file-workspace' });
    return actions;
  }
  if (files.every((file: WorkspaceFile): boolean => file.mime === 'application/pdf')) {
    return files.length === 1 ? [{ title: '压缩 PDF', toolId: 'pdf-compress' },
      { title: '整理页面', toolId: 'pdf-edit' }, { title: '保存在工作区', toolId: 'file-workspace' }] :
      [{ title: '合并 PDF', toolId: 'pdf-merge' }, { title: '保存在工作区', toolId: 'file-workspace' }];
  }
  if (files.length === 1 && (files[0].mime === 'text/csv' || files[0].name.toLowerCase().endsWith('.xlsx'))) {
    return [{ title: '分析表格', toolId: 'analytics' }, { title: '保存在工作区', toolId: 'file-workspace' }];
  }
  return [{ title: '查看工作区', toolId: 'file-workspace' }];
}
