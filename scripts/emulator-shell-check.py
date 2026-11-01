#!/usr/bin/env python3
"""Verify main destinations, help search/expansion and system picker entry points."""
import argparse,json,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--device',default='127.0.0.1:5555');a.add_argument('--theme',choices=['light','dark'],default='light');args=a.parse_args()
OUT=ROOT/'docs/screenshots/emulator'/('shell-'+args.theme);OUT.mkdir(parents=True,exist_ok=True)
NODE='/Users/thousandmiles/.nvm/versions/node/v22.23.2/bin/node';CLI='/Users/thousandmiles/.nvm/versions/node/v22.23.2/lib/node_modules/@deveco/deveco-code/node_modules/@deveco/deveco-cli/cli.js';HDC='/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'
results=[]
def cmd(*parts):
 p=subprocess.run([NODE,CLI,*parts,'--device',args.device],cwd=ROOT,text=True,capture_output=True,timeout=30)
 if p.returncode:raise RuntimeError((p.stdout+p.stderr)[-1200:])
 return p.stdout
def flat(n):return [x for v in n for x in flat(v)] if isinstance(n,list) else [n]+[x for v in n.get('children',[]) for x in flat(v)]
def nodes():return flat(json.loads(cmd('ui','layout','--format','json')))
def tap(n):
 b=n['bounds'];cmd('ui','click',str((b[0]+b[2])//2),str((b[1]+b[3])//2));time.sleep(.25)
def find(key,val):return next((n for n in nodes() if n.get(key)==val),None)
def click(val,key='text'):
 for _ in range(12):
  n=find(key,val)
  if n and (val.startswith('nav-') or 330<(n['bounds'][1]+n['bounds'][3])//2<2650):tap(n);return
  cmd('ui','swipe','1300','550' if n and n['bounds'][3]<330 else '2400','1300','2400' if n and n['bounds'][3]<330 else '550','--speed','2000')
 raise RuntimeError('Missing '+val)
def back():subprocess.run([HDC,'-t',args.device,'shell','uitest uiInput keyEvent Back'],capture_output=True,check=True);time.sleep(.3)
def shot(name):
 p=OUT/(name+'.png');p.unlink(missing_ok=True);cmd('ui','screenshot','--path',str(p))
def text():return '\n'.join(n.get('text','') for n in nodes())
def edge(direction):
 previous=None
 for _ in range(60):
  cmd('ui','swipe','1300','2400' if direction=='up' else '550','1300','550' if direction=='up' else '2400','--speed','2000');current=[(n.get('id'),n.get('text'),n.get('bounds')) for n in nodes()]
  if current==previous:break
  previous=current
def fill(id,value):
 click(id,'id');subprocess.run([HDC,'-t',args.device,'shell','uitest uiInput keyEvent 2072 2017'],capture_output=True,check=True);cmd('ui','text',value);back()
def record(name):results.append({'check':name,'status':'pass'});print(name+' PASS',flush=True)
try:
 click('nav-tab-3','id');click('深色' if args.theme=='dark' else '浅色');time.sleep(.6)
 for index,label in enumerate(['home','tools','history','profile']):
  click('nav-tab-'+str(index),'id');edge('down');shot(label+'-top');edge('up');shot(label+'-bottom');record(label+' top and bottom reachable')
 click('nav-tab-1','id');edge('down');fill('tool-search','json');star=find('id','favorite-json');assert star is not None
 baseline=[n.get('text') for n in flat(star) if n.get('text') in ['★','☆']]
 click('favorite-json','id');time.sleep(.3)
 changed=[n.get('text') for n in flat(find('id','favorite-json')) if n.get('text') in ['★','☆']]
 if changed!=baseline:
  click('favorite-json','id');record('favorite toggles and restores original selection')
 else:record('favorite respects four-tool capacity')
 click('nav-tab-0','id');edge('down');click('自定义')
 original=[n['id'].removeprefix('favorite-') for n in nodes() if n.get('id','').startswith('favorite-') and not n.get('id','').startswith('favorite-up-')]
 if len(original)>1:
  click('favorite-up-'+original[1],'id');edge('down');swapped=[n['id'].removeprefix('favorite-') for n in nodes() if n.get('id','').startswith('favorite-') and not n.get('id','').startswith('favorite-up-')];assert swapped[:2]==[original[1],original[0]]
  click('favorite-up-'+original[0],'id');record('favorite reorder changes and restores order')
 click('nav-tab-3','id');edge('down');click('使用说明');shot('help-top');assert '46 条说明' in text();record('help shows 46 articles')
 fill('help-search','JSON');assert '46 条说明' not in text();edge('up');shot('help-search-json-bottom');assert 'JSON' in text();record('help search finds and expands JSON guides')
 edge('down');fill('help-search','NoSuchLumiKitArticle9876');assert '暂时没有找到相关说明' in text();shot('help-empty');click('查看全部说明');assert '46 条说明' in text();record('help no-result reset restores all articles')
 click('展开全部');edge('up');shot('help-all-bottom');edge('down');click('收起');shot('help-collapsed');record('help expand/collapse all')
 back();click('nav-tab-3','id');edge('down');click('文件工作区');shot('workspace-top');edge('up');shot('workspace-bottom');back();record('workspace route')
 click('隐私与数据');assert '本应用未申请网络' in text();shot('privacy-dialog');back();record('privacy dialog')
 click('关于集萤');shot('about-dialog');back();record('about dialog')
 click('导出数据备份');time.sleep(.6);shot('backup-system-picker');(OUT/'backup-picker-layout.json').write_text(json.dumps(nodes(),ensure_ascii=False,indent=2));back();record('metadata backup opens native save picker; cancellation returns')
 click('恢复备份');time.sleep(.5);shot('restore-system-picker');back();record('restore opens native file picker; cancellation returns')
 click('清理临时缓存');time.sleep(.4);shot('cache-dialog');record('cache cleanup entry responds')
 click('nav-tab-0','id');edge('down');shot('final-home')
except Exception as e:
 results.append({'check':'shell flow','status':'fail','error':str(e)});shot('failure');print(str(e),flush=True)
(OUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
if any(r['status']!='pass' for r in results):raise SystemExit(1)
