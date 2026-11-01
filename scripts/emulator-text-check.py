#!/usr/bin/env python3
"""Exercise text conversion, developer modes, clipboard and validation through native UI."""
import argparse,json,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--device',default='127.0.0.1:5555');args=a.parse_args()
OUT=ROOT/'docs/screenshots/emulator/text-flows';OUT.mkdir(parents=True,exist_ok=True)
NODE='/Users/thousandmiles/.nvm/versions/node/v22.23.2/bin/node';CLI='/Users/thousandmiles/.nvm/versions/node/v22.23.2/lib/node_modules/@deveco/deveco-code/node_modules/@deveco/deveco-cli/cli.js';HDC='/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'
results=[]
def cmd(*parts):
 p=subprocess.run([NODE,CLI,*parts,'--device',args.device],cwd=ROOT,text=True,capture_output=True,timeout=30)
 if p.returncode:raise RuntimeError((p.stdout+p.stderr)[-1200:])
 return p.stdout
def flat(n):return [x for v in n for x in flat(v)] if isinstance(n,list) else [n]+[x for v in n.get('children',[]) for x in flat(v)]
def nodes():return flat(json.loads(cmd('ui','layout','--format','json')))
def tap(n):
 b=n['bounds'];cmd('ui','click',str((b[0]+b[2])//2),str((b[1]+b[3])//2));time.sleep(.2)
def swipe(direction):cmd('ui','swipe','1300','2400' if direction=='up' else '550','1300','550' if direction=='up' else '2400','--speed','2000')
def click(val,key='text'):
 for _ in range(9):
  n=next((n for n in nodes() if n.get(key)==val),None)
  if n and (val.startswith('nav-') or 330<(n['bounds'][1]+n['bounds'][3])//2<2650):tap(n);return
  swipe('down' if n and n['bounds'][3]<330 else 'up')
 raise RuntimeError('Missing '+val)
def back():subprocess.run([HDC,'-t',args.device,'shell','uitest uiInput keyEvent Back'],capture_output=True,check=True);time.sleep(.2)
def shot(name):
 p=OUT/(name+'.png');p.unlink(missing_ok=True);cmd('ui','screenshot','--path',str(p))
def text():return '\n'.join(n.get('text','') for n in nodes())
def edge(direction):
 old=None
 for _ in range(10):
  swipe(direction);new=[(n.get('text'),n.get('bounds')) for n in nodes()]
  if new==old:break
  old=new
def fill(id,value):
 click(id,'id');subprocess.run([HDC,'-t',args.device,'shell','uitest uiInput keyEvent 2072 2017'],capture_output=True,check=True);cmd('ui','text',value);back()
def open_tool(key):
 click('nav-tab-1','id');fill('tool-search',key);click('tool-'+key,'id')
def record(name):results.append({'check':name,'status':'pass'});print(name+' PASS',flush=True)
def execute(expected):
 click('dev-execute','id');time.sleep(.3);edge('up');assert expected in text(),expected+' missing';edge('down')
try:
 for key,source,expected in [('csv-json','name,qty\npen,2\nbook,4','"qty": "2"'),('json-csv','[{"name":"pen","qty":2},{"name":"book","qty":4}]','name,qty'),('text-convert','# LumiKit QA\nOffline note','Offline note')]:
  open_tool(key);fill('file-text-input',source);fill('file-result-name','QA_LumiKit_'+key);click('开始转换');edge('up');assert '转换完成' in text() and expected in text();shot(key+'-result');record(key+' actual conversion result')
  click('保存结果');time.sleep(.5);shot(key+'-native-save-picker');back();record(key+' writes workspace result and opens system save picker')
  if key=='json-csv':
   edge('down');fill('file-text-input','[{"a":{"nested":1}}]');click('开始转换');edge('up');assert '结果预览' not in text() and '保存结果' not in text();shot('invalid-json-csv-clears-old-output');record('invalid replacement input rejects without stale preview or export')
  back()
 click('nav-tab-2','id');edge('down');click('重试');assert 'JSON 转 CSV' in text();shot('failed-conversion-retry');record('durable failed conversion reopens correct tool for retry');back()
 open_tool('json');fill('dev-input','{"a":1,"b":[2]}');click('压缩');execute('{"a":1,"b":[2]}');click('校验');execute('JSON 校验通过');record('JSON minify and validate modes')
 fill('dev-input','{"a":}');click('dev-execute','id');edge('up');assert '已在本地完成处理' not in text();shot('json-invalid');record('invalid JSON rejected');back()
 open_tool('base64');click('解码');fill('dev-input','YWJj');execute('abc');edge('up');click('复制');edge('down');click('清空');click('粘贴');assert 'abc' in text();shot('clipboard-roundtrip');record('Base64 decode and explicit copy/paste');back()
 open_tool('url');click('解码');fill('dev-input','a%20b%2Bc');execute('a b+c');record('URL decode');back()
 open_tool('hash');click('dev-execute','id');edge('up');assert 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' in text();shot('sha256-empty');record('empty input SHA-256 on page');back()
except Exception as e:
 results.append({'check':'text flow','status':'fail','error':str(e)});shot('failure');print(str(e),flush=True)
(OUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
if any(r['status']!='pass' for r in results):raise SystemExit(1)
