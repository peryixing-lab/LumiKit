#!/usr/bin/env python3
"""UI acceptance on a dedicated test emulator. No production device is reset."""
import json, subprocess, time, argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
NODE='/Users/thousandmiles/.nvm/versions/node/v22.23.2/bin/node'
CLI='/Users/thousandmiles/.nvm/versions/node/v22.23.2/lib/node_modules/@deveco/deveco-code/node_modules/@deveco/deveco-cli/cli.js'
p=argparse.ArgumentParser();p.add_argument('--device',required=True);p.add_argument('--phase',choices=['all','files','data'],default='all');args=p.parse_args()
OUT=ROOT/'docs/validation/next-release';OUT.mkdir(parents=True,exist_ok=True)
results=[]
if args.phase=='files' and (OUT/'ui-checks.json').exists():results=json.loads((OUT/'ui-checks.json').read_text()).get('passed',[])
def cmd(*parts):
 proc=subprocess.run([NODE,CLI,*parts,'--device',args.device],cwd=ROOT,capture_output=True,text=True,timeout=35)
 if proc.returncode:raise RuntimeError((proc.stdout+proc.stderr)[-1200:])
 return proc.stdout
def flatten(data):
 if isinstance(data,list):return [n for x in data for n in flatten(x)]
 return [data]+[n for x in data.get('children',[]) for n in flatten(x)]
def nodes():return flatten(json.loads(cmd('ui','layout','--format','json')))
def visible(node):return node.get('bounds') and 190<(node['bounds'][1]+node['bounds'][3])//2<2710
def find(key,text=False,scroll=True):
 for _ in range(10 if scroll else 1):
  found=next((n for n in nodes() if n.get('text' if text else 'id')==key and visible(n)),None)
  if found:return found
  cmd('ui','swipe','1050','2280','1050','650','--speed','2400')
 raise RuntimeError('Control not visible: '+key)
def tap_node(node):
 b=node['bounds'];cmd('ui','click',str((b[0]+b[2])//2),str((b[1]+b[3])//2));time.sleep(.25)
def tap(key,text=False,scroll=True):tap_node(find(key,text,scroll))
def top():
 for _ in range(4):cmd('ui','swipe','1050','650','1050','2280','--speed','2400')
def back():tap('secondary-back',scroll=False)
def shot(name):
 path=OUT/(name+'.png')
 if path.exists():path.unlink()
 cmd('ui','screenshot','--path',str(path))
def check(name,condition):
 if not condition:raise AssertionError(name)
 results.append(name);print('PASS '+name,flush=True)
def text():return '\n'.join(n.get('text','') for n in nodes())
def dismiss_keyboard():
 subprocess.run(['/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc','-t',args.device,'shell','uitest uiInput keyEvent Back'],check=True,capture_output=True,timeout=10);time.sleep(.25)
def enter_search(key):
 tap('nav-tab-1',scroll=False);tap('tool-search',scroll=False);subprocess.run(['/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc','-t',args.device,'shell','uitest uiInput keyEvent 2072 2017'],check=True,capture_output=True,timeout=10);cmd('ui','text',key);dismiss_keyboard()
def open_tool(key):
 enter_search(key);tap('tool-'+key)
if __name__ == '__main__':
 try:
  if args.phase=='all':
   open_tool('forms');tap('检查清单',text=True)
   check('form template opens with real fields','检查日期' in text())
   back();check('unsaved template is retained as a draft','继续草稿' in text())
   tap('forms-resume-draft');check('draft resumes the editor','检查日期' in text())
   tap('forms-duplicate');check('form duplication changes the title','日常检查清单（副本）' in text())
   tap('forms-save-schema');top();shot('forms-template-and-draft');back();back()
  open_tool('image-convert');tap('邮件图片：JPEG / 1280px / 75%',text=True);tap('保存预设',text=True)
  top();tap('预设 · 邮件图片',text=True);check('file preset saved and is available','预设 · 邮件图片' in text());shot('image-preset');back()
  open_tool('pdf-edit');check('PDF organizer is reachable','PDF 页面整理' in text());shot('pdf-organizer-empty');back()
  open_tool('image-ocr');check('OCR tool is reachable','图片文字识别' in text());shot('ocr-tool');back()
  open_tool('analytics');tap('analytics-sample');time.sleep(.5)
  check('CSV sample parses using the native task pool','已解析' in text())
  tap('analytics-export-chart');time.sleep(.6);shot('chart-export-dialog')
  print('CHART_EXPORT_DIALOG '+text(),flush=True)
 except Exception as error:
  print('FAIL '+str(error),flush=True);shot('ui-failure');raise
 finally:
  (OUT/'ui-checks.json').write_text(json.dumps({'device':args.device,'passed':results},ensure_ascii=False,indent=2))
