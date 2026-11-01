#!/usr/bin/env python3
"""Exercise visible LumiKit UI through documented DevEco CLI commands; preserve screenshots and results."""
import argparse, json, subprocess, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
NODE='/Users/thousandmiles/.nvm/versions/node/v22.23.2/bin/node'
CLI='/Users/thousandmiles/.nvm/versions/node/v22.23.2/lib/node_modules/@deveco/deveco-code/node_modules/@deveco/deveco-cli/cli.js'
HDC='/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'
a=argparse.ArgumentParser();a.add_argument('--device',default='127.0.0.1:5555');a.add_argument('--start',type=int,default=0);a.add_argument('--end',type=int,default=22);a.add_argument('--output',default='docs/screenshots/emulator/phone-light');a.add_argument('--visual-only',action='store_true');a.add_argument('--theme',choices=['light','dark']);args=a.parse_args()
OUT=ROOT/args.output;OUT.mkdir(parents=True,exist_ok=True)
results=[]
def cmd(*parts,timeout=20):
 p=subprocess.run([NODE,CLI,*parts,'--device',args.device],cwd=ROOT,text=True,capture_output=True,timeout=timeout)
 if p.returncode:raise RuntimeError((p.stdout+p.stderr)[-1600:])
 return p.stdout
def layout():return json.loads(cmd('ui','layout','--format','json'))
def flatten(data):
 if isinstance(data,list):
  return [node for child in data for node in flatten(child)]
 return [data]+[node for child in data.get('children',[]) for node in flatten(child)]
def nodes():return flatten(layout())
def tap(node):
 b=node['bounds'];cmd('ui','click',str((b[0]+b[2])//2),str((b[1]+b[3])//2));time.sleep(.25)
def text_node(text):return next((n for n in nodes() if n.get('text')==text),None)
def tap_text(text,scroll=True):
 for i in range(6 if scroll else 1):
  n=text_node(text)
  if n and 330<(n['bounds'][1]+n['bounds'][3])//2<2650:tap(n);return
  cmd('ui','swipe','1300','2400','1300','550','--speed','2000')
 raise RuntimeError('Visible control not found: '+text)
def tap_id(key):
 for _ in range(6):
  found=next((n for n in nodes() if n.get('id')==key),None)
  if found and (key.startswith('nav-') or 330<(found['bounds'][1]+found['bounds'][3])//2<2650):tap(found);return
  if key.startswith('nav-'):break
  cmd('ui','swipe','1300','550' if found and found['bounds'][3]<330 else '2400','1300','2400' if found and found['bounds'][3]<330 else '550','--speed','2000')
 raise RuntimeError('Visible node not found: '+key)
def back():subprocess.run([HDC,'-t',args.device,'shell','uitest uiInput keyEvent Back'],capture_output=True,check=True,timeout=10);time.sleep(.25)
def shot(label):
 p=OUT/(label+'.png')
 if p.exists():p.unlink()
 cmd('ui','screenshot','--path',str(p));return str(p.relative_to(ROOT))
def scroll_bottom():
 last=None
 for i in range(12):
  cmd('ui','swipe','1300','2400','1300','550','--speed','2000');time.sleep(.1)
  current=[(n.get('text',''),n.get('bounds')) for n in nodes() if n.get('text')]
  if current==last:break
  last=current
def alltext():return '\n'.join(n.get('text','') for n in nodes())
def open_tool(key,name):
 tap_id('nav-tab-1')
 cmd('ui','click','--id','tool-search')
 subprocess.run([HDC,'-t',args.device,'shell','uitest uiInput keyEvent 2072 2017'],capture_output=True,check=True,timeout=10)
 cmd('ui','text',key);back()
 tap_id('tool-'+key)
def check_title():
 title=next((n for n in nodes() if n.get('id')=='HdsTitleBar'),None)
 assert title is not None,'HDS title bar missing'
 assert title['bounds'][1]>=100,'Title overlaps status area'
 return title['bounds']
TOOLS=[('pdf-merge','PDF 合并'),('pdf-split','PDF 拆分'),('pdf-extract','页面提取'),('pdf-images','PDF 转图片'),('images-pdf','图片转 PDF'),('image-convert','图片转换'),('csv-json','CSV → JSON'),('json-csv','JSON → CSV'),('text-convert','TXT ↔ Markdown'),('inventory','我的物品'),('forms','本地表单'),('json','JSON 格式化'),('base64','Base64'),('url','URL 编码'),('timestamp','时间戳'),('hash','SHA-256 哈希'),('uuid','UUID 生成'),('color','颜色转换'),('diff','文本对比'),('regex','正则测试'),('markdown','Markdown 预览'),('analytics','CSV 数据分析')]
DEVELOPER=set(key for key,_ in TOOLS[11:21])
if args.theme:
 tap_id('nav-tab-3');tap_text('深色' if args.theme=='dark' else '浅色');time.sleep(.7)
for index,(key,name) in enumerate(TOOLS[args.start:args.end],args.start):
 entry={'index':index,'tool':key,'name':name,'checks':[]}
 try:
  open_tool(key,name)
  entry['titleBounds']=check_title();entry['top']=shot(key+'-top');entry['checks'].append('HDS title within status safe area')
  if key in DEVELOPER and not args.visual_only:
   if key!='uuid':tap_text('填入示例')
   if key!='markdown':
    tap_id('dev-execute');time.sleep(.8)
    scroll_bottom()
    assert '已在本地完成处理' in alltext(),'Developer result did not report success'
    entry['checks'].append('sample input processed successfully on emulator')
   else:
    scroll_bottom();assert '我们相信' in alltext(),'Markdown preview missing';entry['checks'].append('native Markdown preview rendered')
  elif key=='analytics' and not args.visual_only:
   tap_text('体验示例');time.sleep(.6);scroll_bottom();assert '保存分析项目' in alltext(),'CSV results not rendered';entry['checks'].append('CSV sample parsed and chart/export sections rendered')
  else:scroll_bottom()
  entry['bottom']=shot(key+'-bottom');entry['status']='pass'
  back()
 except Exception as error:
  entry['status']='fail';entry['error']=str(error)
  try:entry['failureScreenshot']=shot(key+'-failure')
  except Exception:pass
  print(json.dumps(entry,ensure_ascii=False),flush=True);results.append(entry);break
 results.append(entry);print(json.dumps(entry,ensure_ascii=False),flush=True)
(OUT/f'results-{args.start}-{args.end}.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
print('Completed',len(results),'tools;',sum(r['status']=='pass' for r in results),'passed',flush=True)

if any(r['status']!='pass' for r in results):raise SystemExit(1)
