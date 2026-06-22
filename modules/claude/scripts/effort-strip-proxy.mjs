#!/usr/bin/env node
// Local Anthropic API proxy that deletes the `effort` parameter from JSON
// request bodies. Claude Code force-sends `effort` for model IDs it doesn't
// recognize (its capability fetch is feature-flagged off as of 2.1.176), so
// research models that lack effort support 400 on every request. Point
// ANTHROPIC_BASE_URL at this proxy to launch Claude Code against such models.
//
// Usage: node effort-strip-proxy.mjs <port>   (0 = ephemeral)
// Prints "LISTENING <port>" on stdout once bound. Forwards everything to
// https://api.anthropic.com, streaming responses (including SSE) straight
// through.
import http from "node:http";
import https from "node:https";

const port = Number(process.argv[2]);
if (!Number.isInteger(port) || port < 0) {
  console.error("usage: effort-strip-proxy.mjs <port>");
  process.exit(1);
}

const UPSTREAM = "api.anthropic.com";

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    let body = Buffer.concat(chunks);
    if (body.length > 0) {
      try {
        const parsed = JSON.parse(body.toString("utf8"));
        if (parsed && typeof parsed === "object") {
          if (process.env.EFFORT_PROXY_DEBUG) {
            console.error(`[proxy] ${req.method} ${req.url} enc=${req.headers["content-encoding"] ?? "none"} keys=${Object.keys(parsed).join(",")}`);
          }
          let stripped = false;
          if ("effort" in parsed) {
            delete parsed.effort;
            stripped = true;
          }
          if (parsed.output_config && typeof parsed.output_config === "object" && "effort" in parsed.output_config) {
            delete parsed.output_config.effort;
            if (Object.keys(parsed.output_config).length === 0) delete parsed.output_config;
            stripped = true;
          }
          if (stripped) body = Buffer.from(JSON.stringify(parsed), "utf8");
        }
      } catch {
        if (process.env.EFFORT_PROXY_DEBUG) {
          console.error(`[proxy] ${req.method} ${req.url} enc=${req.headers["content-encoding"] ?? "none"} unparseable body (${body.length}B)`);
        }
      }
    }
    const headers = { ...req.headers, host: UPSTREAM };
    delete headers["content-length"];
    if (body.length > 0) headers["content-length"] = String(body.length);
    const upstream = https.request(
      { host: UPSTREAM, method: req.method, path: req.url, headers },
      (upRes) => {
        res.writeHead(upRes.statusCode, upRes.headers);
        upRes.pipe(res);
      },
    );
    upstream.on("error", (err) => {
      res.writeHead(502, { "content-type": "application/json" });
      res.end(JSON.stringify({ type: "error", error: { type: "proxy_error", message: String(err) } }));
    });
    upstream.end(body);
  });
});

server.listen(port, "127.0.0.1", () => {
  console.log(`LISTENING ${server.address().port}`);
});
