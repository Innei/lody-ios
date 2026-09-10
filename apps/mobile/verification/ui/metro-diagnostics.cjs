const { performance } = require('node:perf_hooks');

// Log only local manifest/status requests. Never record headers or response bodies.
module.exports =
  (next, log = console.log) =>
  (req, res) => {
    const path = req.url?.split('?')[0];
    if (path === '/' || path === '/status') {
      const started = performance.now();
      const entry = {
        method: req.method,
        path,
        startedAt: new Date().toISOString(),
      };
      log(JSON.stringify({ metroRequest: 'start', ...entry }));
      res.once('close', () => {
        log(
          JSON.stringify({
            metroRequest: 'end',
            ...entry,
            status: res.statusCode,
            finished: res.writableFinished,
            milliseconds: Math.round(performance.now() - started),
          }),
        );
      });
    }
    return next(req, res);
  };

// Expo serves manifests before Metro's enhanceMiddleware. Observe the HTTP server
// itself so a request stuck in Expo middleware is still visible in the log.
if (process.env.LODY_UI_METRO_DIAGNOSTICS === '1') {
  const { Server } = require('node:http');
  const emit = Server.prototype.emit;
  Server.prototype.emit = function (event, ...args) {
    if (event === 'request') {
      return module.exports(() => emit.call(this, event, ...args))(...args);
    }
    return emit.call(this, event, ...args);
  };
}
