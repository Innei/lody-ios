"""Send a CDP command only to the App on the named Simulator."""
import json
import subprocess


def inspector(udid, port, method, params=None):
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json'], text=True))
    name = next(d['name'] for group in devices['devices'].values() for d in group if d['udid'] == udid)
    result = subprocess.run(['node', '-e', r"""
const WebSocket = require('ws');
(async () => {
  const origin = `http://127.0.0.1:${process.argv[1]}`;
  const targets = await (await fetch(`${origin}/json/list`)).json();
  const matches = targets.filter(t => t.deviceName === process.argv[2] && t.appId === 'app.innei.lody');
  if (matches.length !== 1) throw new Error(`Expected one inspector for ${process.argv[2]}, found ${matches.length}`);
  const socket = new WebSocket(matches[0].webSocketDebuggerUrl, { origin });
  const timer = setTimeout(() => { socket.terminate(); process.exitCode = 1; }, 8000);
  socket.on('open', () => socket.send(JSON.stringify({ id: 1, method: process.argv[3], params: JSON.parse(process.argv[4]) })));
  socket.on('message', raw => {
    const message = JSON.parse(raw);
    if (message.id !== 1) return;
    clearTimeout(timer);
    if (message.error) { console.error(message.error); process.exitCode = 1; }
    console.log(JSON.stringify(message));
    socket.close();
  });
  socket.on('error', error => { clearTimeout(timer); console.error(error); process.exitCode = 1; });
})().catch(error => { console.error(error); process.exitCode = 1; });
""", str(port), name, method, json.dumps(params or {})], check=True, timeout=12, capture_output=True, text=True)
    response = json.loads(result.stdout)['result']
    if response.get('exceptionDetails'):
        raise RuntimeError(response['exceptionDetails'])
    return response
