import { common } from '@kit.AbilityKit';
import { FileService, WorkspaceFile } from '../../core/FileService';
import { LocalAttachment } from './InventoryModels';

/** Shared private workspace copies keep attachments available to the other tools. */
export class InventoryFiles {
  static async attach(context: common.UIAbilityContext): Promise<LocalAttachment[]> {
    const files = await FileService.pickFiles(context, [], 5);
    return files.map((file: WorkspaceFile) => {
      const attachment = new LocalAttachment();
      attachment.id = file.id;
      attachment.name = file.name;
      attachment.path = file.path;
      attachment.size = file.size;
      return attachment;
    });
  }

  static async save(context: common.UIAbilityContext, data: string, filename: string,
    suffix: string): Promise<string> {
    const path = await FileService.writeText(context, filename, data);
    await FileService.exportFile(context, path, filename);
    return path;
  }

  static async exportAttachment(context: common.UIAbilityContext, attachment: LocalAttachment): Promise<boolean> {
    const path = await FileService.exportFile(context, attachment.path, attachment.name);
    return path.length > 0;
  }
}
