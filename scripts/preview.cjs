#!/usr/bin/env node
/**
 * Capture the actual ArkUI app with the DevEco SDK Previewer; no signing required.
 *   node scripts/preview.cjs --build
 *   node scripts/preview.cjs --interactive
 * Interactive stdin accepts one JSON request per line:
 *   {"click":[426,2115]}
 *   {"save":"/absolute/path/screen.jpg"}
 *   {"command":"BackClick","args":{}}
 *   {"exit":true}
 * The Previewer needs local Unix-socket and loopback-network access.
 */
const fs = require('node:fs');
const os = require('node:os');
const net = require('node:net');
const cp = require('node:child_process');
const path = require('node:path');
const readline = require('node:readline');

const project = path.resolve(__dirname, '..');
const deveco = process.env.LUMIKIT_DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents';
const sdk = process.env.DEVECO_SDK_HOME || path.join(deveco, 'sdk');
const sdkDefault = path.join(sdk, 'default');
const previewerBin = path.join(sdkDefault, 'openharmony/previewer/common/bin');
const previewRoot = path.join(project, 'entry/.preview/default/intermediates');
const outputDir = path.join(project, 'docs/screenshots');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'lumikit-preview-'));
const logPath = path.join(scratch, 'previewer.log');
const log = fs.createWriteStream(logPath);
const socketPrefix = `lumikit_${process.pid}`;
const socketPath = `/tmp/${socketPrefix}_commandPipe`;
const sid = require('node:crypto').randomBytes(16).toString('hex');
const interactive = process.argv.includes('--interactive');
const width = 1080;
const height = 2340;
let child;
let commandServer;
let commandSocket;
let imageSocket;
let lastJpeg;
let frameCount = 0;
let frameTime = 0;
let inspector;
let pipeBuffer = '';
let stopped = false;
let input;

function delay(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }
function required(filename) {
  if (!fs.existsSync(filename)) throw new Error(`Missing ${filename}. Run with --build first.`);
}
async function buildPreview() {
  const node = path.join(deveco, 'tools/node/bin/node');
  const hvigor = path.join(deveco, 'tools/hvigor/hvigor/bin/hvigor.js');
  required(node);
  required(hvigor);
  await new Promise((resolve, reject) => {
    let succeeded = false;
    const build = cp.spawn(node, [hvigor, '--mode', 'module', '-p', 'product=default', '-p', 'module=entry@default',
      '-p', 'pageType=page', '-p', 'previewMode=true', '-p', 'buildRoot=.preview', 'PreviewBuild', '--no-daemon'], {
      cwd: project,
      env: { ...process.env, DEVECO_SDK_HOME: sdk, JAVA_HOME: path.join(deveco, 'jbr/Contents/Home'),
        PATH: path.dirname(node) + path.delimiter + process.env.PATH }
    });
    const deadline = setTimeout(() => { build.kill('SIGTERM'); reject(new Error('PreviewBuild timed out.')); }, 60000);
    const onData = buffer => {
      process.stdout.write(buffer);
      if (buffer.toString().includes('BUILD SUCCESSFUL')) {
        succeeded = true;
        // PreviewBuild leaves its watch worker running even without --watch.
        setTimeout(() => build.kill('SIGINT'), 100);
      }
    };
    build.stdout.on('data', onData);
    build.stderr.on('data', onData);
    build.on('error', reject);
    build.on('exit', code => {
      clearTimeout(deadline);
      succeeded ? resolve() : reject(new Error(`PreviewBuild failed (${code}).`));
    });
  });
}
async function availablePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      server.close(() => resolve(port));
    });
  });
}
function handlePipe(buffer) {
  pipeBuffer += buffer.toString();
  let separator;
  while ((separator = pipeBuffer.indexOf('\0')) >= 0) {
    const message = pipeBuffer.slice(0, separator);
    pipeBuffer = pipeBuffer.slice(separator + 1);
    try {
      const value = JSON.parse(message);
      if (value.command === 'inspector' && value.result) inspector = JSON.parse(value.result);
    } catch { /* Ignore non-JSON engine diagnostics. */ }
  }
}
async function startPreview() {
  const binary = path.join(previewerBin, 'Previewer');
  const abc = path.join(previewRoot, 'loader_out/default/ets');
  const resources = path.join(previewRoot, 'res/default');
  const loader = path.join(previewRoot, 'loader/default/loader.json');
  for (const file of [binary, path.join(abc, 'modules.abc'), path.join(resources, 'resources.index'), loader]) required(file);
  const wsPath = path.join(deveco, 'tools/hvigor/hvigor/node_modules/ws');
  required(wsPath);
  const WS = require(wsPath);
  const port = await availablePort();
  await new Promise((resolve, reject) => {
    commandServer = net.createServer(socket => {
      commandSocket = socket;
      socket.on('data', handlePipe);
    });
    commandServer.on('error', reject);
    commandServer.listen(socketPath, resolve);
  });
  const args = [
    // Enable the SDK's local-test file mode. Otherwise native Preferences cannot
    // resolve the mocked Context directory and initialization fails.
    '-ilt', 'true', '-refresh', 'full', '-projectID', '2128223959',
    '-j', abc, '-s', socketPrefix, '-cpm', 'false', '-device', 'phone', '-shape', 'rect',
    '-sd', '480', '-or', String(width), String(height), '-cr', String(width), String(height),
    '-f', path.join(deveco, 'plugins/codegenie-plugin/previewProjectTemplate/phoneSettingConfig_Phone.json'),
    '-ljPath', loader, '-n', 'entry', '-av', 'ACE_2_0', '-url', 'pages/Index', '-pages', 'main_pages',
    '-arp', resources, '-pm', 'Stage', '-hsp', path.join(sdkDefault, 'hms/previewer'),
    '-l', 'zh_CN', '-cm', 'light', '-o', 'portrait', '-lws', String(port), '-sid', sid
  ];
  child = cp.spawn(binary, args, { cwd: previewerBin });
  child.stdout.pipe(log, { end: false });
  child.stderr.pipe(log, { end: false });
  child.on('error', error => { console.error(error.message); cleanup(); });
  child.on('exit', (code, signal) => {
    if (!stopped) console.error(`Previewer exited (${code || signal}). See ${logPath}`);
  });
  for (let attempt = 0; attempt < 30; attempt++) {
    const connected = await new Promise(resolve => {
      const socket = new WS(`ws://127.0.0.1:${port}/${sid}`);
      socket.on('error', () => resolve(false));
      socket.on('open', () => { imageSocket = socket; resolve(true); });
      socket.on('message', (buffer, binaryMessage) => {
        if (!binaryMessage || buffer.length <= 40) return;
        // SDK image messages have a 40-byte region header, followed by JPEG data.
        const jpeg = buffer.subarray(40);
        if (jpeg[0] !== 0xff || jpeg[1] !== 0xd8) return;
        lastJpeg = jpeg;
        frameCount++;
        frameTime = Date.now();
      });
    });
    if (connected) return;
    await delay(150);
  }
  throw new Error(`Image WebSocket did not start. See ${logPath}`);
}
async function stableFrame(afterCount = 0) {
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    if (frameCount > afterCount && Date.now() - frameTime > 550) return;
    await delay(75);
  }
  throw new Error(`No stable rendered frame. See ${logPath}`);
}
function command(name, args = {}, type = 'action') {
  if (!commandSocket) throw new Error('Previewer command socket is unavailable.');
  commandSocket.write(JSON.stringify({ version: '1.0.1', command: name, type, args }) + '\n');
}
async function click(x, y) {
  const framesBefore = frameCount;
  command('MousePress', { x, y, duration: 0 });
  await delay(80);
  command('MouseRelease', { x, y, duration: 0 });
  await stableFrame(framesBefore);
}
function save(filename) {
  if (!lastJpeg) throw new Error('No image has been rendered.');
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, lastJpeg);
  console.log(`Saved ${path.relative(project, filename)}`);
}
function contents(node, values = []) {
  if (!node) return values;
  if (node.$attrs && node.$attrs.content) values.push(node.$attrs.content);
  for (const entry of node.$children || []) contents(entry, values);
  return values;
}
async function capture() {
  await stableFrame();
  await delay(300);
  const text = contents(inspector).join('\n');
  if (text.includes('重新打开本地数据')) throw new Error(`App initialization failed. See ${logPath}`);
  save(path.join(outputDir, 'phone-home.jpg'));
  await click(426, 2115);
  save(path.join(outputDir, 'phone-tools.jpg'));
  await click(882, 2115);
  save(path.join(outputDir, 'phone-profile.jpg'));
}
function cleanup() {
  if (stopped) return;
  stopped = true;
  clearTimeout(globalTimeout);
  if (input) input.close();
  if (imageSocket) imageSocket.close();
  if (commandSocket) commandSocket.destroy();
  if (commandServer) commandServer.close();
  if (child && child.exitCode === null) child.kill('SIGTERM');
  try { fs.unlinkSync(socketPath); } catch {}
  log.end();
}
process.on('SIGINT', cleanup);
process.on('SIGTERM', cleanup);
const globalTimeout = setTimeout(() => { console.error('Preview session timed out.'); cleanup(); }, interactive ? 300000 : 90000);
async function main() {
  if (process.argv.includes('--build')) await buildPreview();
  await startPreview();
  console.log(`Previewer log: ${logPath}`);
  if (interactive) {
    await stableFrame();
    console.log('Interactive preview ready. Send one JSON request per line.');
    input = readline.createInterface({ input: process.stdin });
    input.on('line', async line => {
      try {
        const request = JSON.parse(line);
        if (request.click) await click(request.click[0], request.click[1]);
        else if (request.save) save(path.resolve(request.save));
        else if (request.exit) cleanup();
        else command(request.command, request.args || {}, request.type || 'action');
      } catch (error) { console.error(error.message); }
    });
  } else {
    await capture();
    cleanup();
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; cleanup(); }).finally(() => {
  if (!interactive || stopped) clearTimeout(globalTimeout);
});
