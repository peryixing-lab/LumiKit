import { isValidDate } from './InventoryModels';

export class LumiReceiptCandidates {
  name: string = '';
  purchaseDate: string = '';
  price: string = '';
}
/** Conservative local extraction: only explicit labels; ambiguous values stay empty for review. */
export function receiptCandidates(text: string): LumiReceiptCandidates {
  const result = new LumiReceiptCandidates();
  const lines = text.replace(/\r\n?/g, '\n').split('\n').map((line: string) => line.trim()).filter((line: string) => !!line);
  const names: string[] = []; const dates: string[] = []; const amounts: string[] = [];
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index]; const following = lines[index + 1] || '';
    const content = line + (/[：:]\s*$/.test(line) ? following : '');
    const name = /^(?:商品名称|物品名称|产品名称)\s*[：:]\s*(.{1,80})$/.exec(content);
    if (name) { names.push(name[1].trim()); }
    const date = /(?:购买日期|交易日期|支付时间|下单时间|开票日期)\s*[：:]?\s*(\d{4})[年/.\-](\d{1,2})[月/.\-](\d{1,2})日?/.exec(content);
    if (date) { const candidate = date[1] + '-' + date[2].padStart(2, '0') + '-' + date[3].padStart(2, '0'); if (isValidDate(candidate)) { dates.push(candidate); } }
    const amount = /(?:实付金额|实付款|实付|价税合计(?:\s*[（(]小写[)）])?|合计金额)\s*[：:]?\s*[¥￥]?\s*(\d+(?:,\d{3})*(?:\.\d{1,2})?)(?:元|\s|$)/.exec(content);
    if (amount) { const number = Number(amount[1].replace(/,/g, '')); if (Number.isFinite(number) && number >= 0 && number <= 100000000) { amounts.push(number.toFixed(2)); } }
  }
  if (new Set(names).size === 1) { result.name = names[0]; }
  if (new Set(dates).size === 1) { result.purchaseDate = dates[0]; }
  if (new Set(amounts).size === 1) { result.price = amounts[0]; }
  return result;
}
