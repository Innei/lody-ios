import { createServer } from 'node:http';
import WebSocket from 'ws';

// Loopback-only synthetic old CLI / fallback endpoint. No Simulator, account,
// credentials, tunnel or external service is contacted by these checks.
const stats = {
  sockets: [],
  controls: [],
  inputs: [],
  redirects: 0,
  hanging: 0,
};
const waiting = [];
const server = createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  res.setHeader('Content-Type', 'application/json');
  if (url.pathname === '/stats') return res.end(JSON.stringify(stats));
  if (url.pathname.endsWith('/control')) {
    stats.controls.push(url.pathname);
    return res.end('{"success":true}');
  }
  if (url.pathname === '/leak') stats.redirects++;
  if (url.pathname.startsWith('/hanging/')) {
    stats.hanging++;
    waiting.splice(0).forEach((response) => response.end('{}'));
    return;
  }
  if (url.pathname === '/await-hanging') {
    if (stats.hanging) return res.end('{}');
    waiting.push(res);
    return;
  }
  if (url.pathname.startsWith('/redirect/')) {
    res.writeHead(302, { Location: '/leak' });
    return res.end();
  }
  if (url.pathname.startsWith('/malformed/')) {
    return res.end('{"iceServers":[{"urls":["https://invalid.example"]}]}');
  }
  res.writeHead(404);
  res.end('{}');
});
const sockets = new WebSocket.Server({ server });
sockets.on('connection', (socket, req) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.searchParams.get('token') !== 'synthetic') {
    socket.close(1008);
    return;
  }
  stats.sockets.push(url.pathname);
  socket.send('fallback-ready');
  socket.on('message', (data) => {
    stats.inputs.push(JSON.parse(data.toString()));
    socket.send(data, { binary: false });
  });
});
server.listen(0, '127.0.0.1', () => {
  console.log(`http://127.0.0.1:${server.address().port}`);
});
