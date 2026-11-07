import { WorkspaceFile } from './FileService';
import { LumiCollection } from '../features/workbench/WorkbenchModels';

/** Shared metadata search for home and workspace; never opens document contents. */
export class WorkspaceSearch {
  static matches(file: WorkspaceFile, query: string, collections: LumiCollection[] = []): boolean {
    const term = query.trim().toLowerCase();
    if (!term) { return true; }
    const collection = collections.find((entry: LumiCollection): boolean => entry.id === file.collectionId);
    const text = [file.name, (file.tags || []).join(' '), collection ? collection.name : ''].join(' ').toLowerCase();
    return term.split(/\s+/).every((word: string): boolean => text.includes(word));
  }
}
