export class LocalAttachment {
  id: string = '';
  name: string = '';
  path: string = '';
  size: number = 0;
}

export class LendingRecord {
  id: string = '';
  borrower: string = '';
  lentAt: string = '';
  returnedAt: string = '';
  dueDate?: string;
}

export class InventoryItem {
  id: string = '';
  name: string = '';
  category: string = '未分类';
  brand: string = '';
  model: string = '';
  purchaseDate: string = '';
  price: string = '';
  warrantyDate: string = '';
  warrantyReminderDate?: string;
  channel: string = '';
  notes: string = '';
  archived: boolean = false;
  attachments: LocalAttachment[] = [];
  lending: LendingRecord[] = [];
  createdAt: number = 0;
}

export function validAttachment(attachment: LocalAttachment): boolean {
  return attachment !== null && typeof attachment === 'object' && typeof attachment.id === 'string' &&
    typeof attachment.name === 'string' && typeof attachment.path === 'string' && typeof attachment.size === 'number';
}

export function validInventoryItem(item: InventoryItem): boolean {
  return item !== null && typeof item === 'object' && typeof item.id === 'string' && typeof item.name === 'string' &&
    typeof item.category === 'string' && typeof item.brand === 'string' && typeof item.model === 'string' &&
    typeof item.purchaseDate === 'string' && typeof item.price === 'string' && typeof item.warrantyDate === 'string' &&
    (item.warrantyReminderDate === undefined || (typeof item.warrantyReminderDate === 'string' && (!item.warrantyReminderDate || isValidDate(item.warrantyReminderDate)))) && typeof item.channel === 'string' && typeof item.notes === 'string' && typeof item.archived === 'boolean' &&
    Array.isArray(item.attachments) && item.attachments.every(validAttachment) && Array.isArray(item.lending) &&
    item.lending.every((loan: LendingRecord) => loan !== null && typeof loan === 'object' &&
      typeof loan.id === 'string' && typeof loan.borrower === 'string' && typeof loan.lentAt === 'string' && typeof loan.returnedAt === 'string' && (loan.dueDate === undefined || (typeof loan.dueDate === 'string' && (!loan.dueDate || isValidDate(loan.dueDate)))));
}

export function localDate(value: Date): string {
  const month = `${value.getMonth() + 1}`.padStart(2, '0');
  const day = `${value.getDate()}`.padStart(2, '0');
  return `${value.getFullYear()}-${month}-${day}`;
}

export function isValidDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) { return false; }
  const parts = value.split('-').map((part: string) => Number(part));
  const date = new Date(parts[0], parts[1] - 1, parts[2]);
  return localDate(date) === value;
}

let lumiLocalSequence: number = 0;

export function newLocalId(prefix: string): string {
  lumiLocalSequence++;
  return `${prefix}_${Date.now()}_${lumiLocalSequence}_${Math.floor(Math.random() * 1000000)}`;
}
