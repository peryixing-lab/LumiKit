import subprocess,json,time
from pathlib import Path
NODE="/Users/thousandmiles/.nvm/versions/node/v22.23.2/bin/node"
CLI="/Users/thousandmiles/.nvm/versions/node/v22.23.2/lib/node_modules/@deveco/deveco-code/node_modules/@deveco/deveco-cli/cli.js"
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
DEVICE="127.0.0.1:5555"
OUT=Path("docs/validation/scroll-fix");OUT.mkdir(parents=True,exist_ok=True)
results=[]
def cmd(*p):
 r=subprocess.run([NODE,CLI,*p,"--device",DEVICE],capture_output=True,text=True,timeout=25)
 if r.returncode:raise RuntimeError(r.stderr+r.stdout)
 return r.stdout
def flat(n):return [x for v in n for x in flat(v)] if isinstance(n,list) else [n]+[x for v in n.get("children",[]) for x in flat(v)]
def nodes():return flat(json.loads(cmd("ui","layout","--format","json")))
def find(key,value):return next((n for n in nodes() if n.get(key)==value),None)
def tap(n):
 b=n["bounds"];cmd("ui","click",str((b[0]+b[2])//2),str((b[1]+b[3])//2));time.sleep(.2)
def click(id):
 n=find("id",id);assert n is not None,id;tap(n)
def back():subprocess.run([HDC,"-t",DEVICE,"shell","uitest uiInput keyEvent Back"],capture_output=True,check=True);time.sleep(.25)
def swipe(x,y1,y2):cmd("ui","swipe",str(x),str(y1),str(x),str(y2),"--speed","1000");time.sleep(.25)
def shot(name):
 p=OUT/(name+".png");p.unlink(missing_ok=True);cmd("ui","screenshot","--path",str(p.resolve()))
def moved(before,id):
 after=find("id",id)
 return after is None or before[1]-after["bounds"][1]>80
try:
 click("nav-tab-1");click("nav-tab-0")
 grid=next(n for n in nodes() if n.get("type")=="Grid");b=grid["bounds"];before=b[1]
 x=b[0]+(b[2]-b[0])//4;y=min(2410,max(700,b[1]+120))
 swipe(x,y,max(450,y-1000));after=next((n for n in nodes() if n.get("type")=="Grid"),None)
 assert after is None or before-after["bounds"][1]>80,"Home card drag did not move page"
 results.append({"case":"home drag starts on category grid","pass":True});shot("home-center-drag");print(results[-1],flush=True)
 click("nav-tab-1");click("tool-search")
 subprocess.run([HDC,"-t",DEVICE,"shell","uitest uiInput keyEvent 2072 2017"],capture_output=True,check=True)
 cmd("ui","text","diff");back();click("tool-diff")
 first=find("id","dev-input");assert first is not None;before=first["bounds"];x=(before[0]+before[2])//2;y=(before[1]+before[3])//2
 swipe(x,y,max(380,y-650));assert moved(before,"dev-input"),"Idle text area still consumes page drag"
 results.append({"case":"page drag starts inside idle TextArea","pass":True});shot("textarea-center-drag");print(results[-1],flush=True)
 swipe(660,650,2250)
 first=find("id","dev-input");assert first is not None;tap(first);back()
 first=find("id","dev-input");before=first["bounds"];x=(before[0]+before[2])//2;y=(before[1]+before[3])//2
 swipe(x,y,max(380,y-650));assert moved(before,"dev-input"),"Text area consumes page drag after keyboard closes"
 results.append({"case":"page drag after keyboard dismissal","pass":True});shot("textarea-after-keyboard");print(results[-1],flush=True)
 back();click("nav-tab-0");shot("final-home")
except Exception as e:
 results.append({"case":"scroll regression","pass":False,"error":str(e)});shot("failure");print(results[-1],flush=True)
(OUT/"results.json").write_text(json.dumps(results,ensure_ascii=False,indent=2))
if any(not r["pass"] for r in results):raise SystemExit(1)
