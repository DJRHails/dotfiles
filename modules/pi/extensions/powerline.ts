import { execSync } from "node:child_process";
import { hostname } from "node:os";
import { basename } from "node:path";
import type {
  ExtensionAPI,
  ExtensionContext,
  ReadonlyFooterDataProvider,
  Theme,
} from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";

// Powerline footer for pi.
//
// Replaces the default footer with a richer, coloured two-line status block:
//
//   <model> (<provider>) 📁 <cwd> @ <host> │ 🌿 <branch> <commit>
//   <ctx-bar> NN% │ ↑in ↓out R<read> W<write> │ $cost (sub) │ <session-id> │ <statuses…>
//
// The context bar shows context-window usage (fills up, red past 90%). setFooter()
// replaces the ENTIRE built-in footer, so the second line re-renders the extension
// statuses ourselves (to keep contributions like "✓ fzf agents") alongside the full
// session id. Widgets (above/below the editor, e.g. the subagents "auto mode" hint)
// are unaffected.

/** Truecolour accent palette, tuned to read against a dark theme. */
const PALETTE = {
  path: "#61afef", // blue
  host: "#c678dd", // purple
  branch: "#98c379", // green
  bar: "#d7af5f", // gold
  danger: "#e06c75", // red
} as const;

const RESET = "\x1b[0m";
const BAR_CELLS = 10;

/** Emit a 24-bit foreground escape for a `#rrggbb` colour. */
function paint(hex: string, text: string): string {
  const n = Number.parseInt(hex.slice(1), 16);
  return `\x1b[38;2;${(n >> 16) & 255};${(n >> 8) & 255};${n & 255}m${text}${RESET}`;
}

/** Rolled-up token/cost usage for the whole session. */
interface SessionUsage {
  cost: number;
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
}

/** Single walk over assistant messages, summing tokens and cost. */
function collectUsage(ctx: ExtensionContext): SessionUsage {
  const usage: SessionUsage = { cost: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
  for (const entry of ctx.sessionManager.getEntries()) {
    if (entry.type !== "message" || entry.message.role !== "assistant") continue;
    const u = entry.message.usage;
    usage.cost += u.cost.total;
    usage.input += u.input;
    usage.output += u.output;
    usage.cacheRead += u.cacheRead;
    usage.cacheWrite += u.cacheWrite;
  }
  return usage;
}

/** Compact token count: 999 · 12.4k · 340k · 1.2M. */
function formatTokens(n: number): string {
  if (n < 1000) return `${n}`;
  if (n < 10_000) return `${(n / 1000).toFixed(1)}k`;
  if (n < 1_000_000) return `${Math.round(n / 1000)}k`;
  if (n < 10_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  return `${Math.round(n / 1_000_000)}M`;
}

/** Cost to 2 significant figures: $380 · $5.2 · $0.046. */
function formatCost(n: number): string {
  if (n <= 0) return "$0";
  return `$${Number(n.toPrecision(2))}`;
}

/** Restyled token counters: dim labels, muted numbers. */
function tokensGroup(theme: Theme, usage: SessionUsage): string {
  const label = (s: string) => theme.fg("dim", s);
  const num = (s: string) => theme.fg("muted", s);
  const parts = [`${label("↑")}${num(formatTokens(usage.input))}`, `${label("↓")}${num(formatTokens(usage.output))}`];
  if (usage.cacheRead) parts.push(`${label("R")}${num(formatTokens(usage.cacheRead))}`);
  if (usage.cacheWrite) parts.push(`${label("W")}${num(formatTokens(usage.cacheWrite))}`);
  return parts.join(" ");
}

/** Gold fuel-gauge for context usage; turns red past 90%. */
function contextBar(theme: Theme, percent: number | null): string {
  if (percent === null) return theme.fg("dim", "░".repeat(BAR_CELLS));
  const filled = Math.max(0, Math.min(BAR_CELLS, Math.round((percent / 100) * BAR_CELLS)));
  const colour = percent > 90 ? PALETTE.danger : PALETTE.bar;
  return paint(colour, "█".repeat(filled)) + theme.fg("dim", "░".repeat(BAR_CELLS - filled));
}

/** First line: model · folder@host · branch commit. */
function identityLine(theme: Theme, ctx: ExtensionContext, branch: string | null, commit: string): string {
  const sep = theme.fg("dim", "│");
  const model = theme.fg("dim", ctx.model?.id ?? "no-model");
  const provider = ctx.model?.provider ? theme.fg("dim", ` (${ctx.model.provider})`) : "";
  const folder = `📁 ${paint(PALETTE.path, basename(ctx.cwd) || ctx.cwd)}`;
  const host = `${theme.fg("dim", "@")} ${paint(PALETTE.host, hostname().split(".")[0])}`;
  let line = `${model}${provider} ${folder} ${host}`;
  if (branch) {
    const commitStr = commit ? ` ${theme.fg("dim", commit)}` : "";
    line += ` ${sep} 🌿 ${paint(PALETTE.branch, branch)}${commitStr}`;
  }
  return line;
}

/** Second-line metrics: context bar · tokens · cost. */
function metricsLine(theme: Theme, ctx: ExtensionContext): string {
  const sep = theme.fg("dim", "│");
  const percent = ctx.getContextUsage()?.percent ?? null;
  const bar = contextBar(theme, percent);
  const pctText = theme.fg("text", percent === null ? "?%" : `${Math.round(percent)}%`);
  const usage = collectUsage(ctx);
  const tokens = tokensGroup(theme, usage);
  const onSub = ctx.model ? ctx.modelRegistry.isUsingOAuth(ctx.model) : false;
  const cost = paint(PALETTE.bar, formatCost(usage.cost)) + (onSub ? theme.fg("dim", " (sub)") : "");
  return `${bar} ${pctText} ${sep} ${tokens} ${sep} ${cost}`;
}

/** Sanitised, alphabetically sorted extension statuses (one line). */
function statusLine(footerData: ReadonlyFooterDataProvider): string | undefined {
  const statuses = footerData.getExtensionStatuses();
  if (statuses.size === 0) return undefined;
  return Array.from(statuses.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([, text]) => text.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim())
    .join(" ");
}

function renderPowerline(
  width: number,
  theme: Theme,
  footerData: ReadonlyFooterDataProvider,
  ctx: ExtensionContext | undefined,
  commit: string,
): string[] {
  if (!ctx) return [];
  const branch = footerData.getGitBranch();
  const sep = theme.fg("dim", "│");
  const sessionId = theme.fg("dim", ctx.sessionManager.getSessionId());
  const statuses = statusLine(footerData);
  let metrics = `${metricsLine(theme, ctx)} ${sep} ${sessionId}`;
  if (statuses) metrics += ` ${sep} ${statuses}`;
  const lines = [identityLine(theme, ctx, branch, commit), metrics];
  return lines.map((line) => truncateToWidth(line, width, theme.fg("dim", "…")));
}

export default function (pi: ExtensionAPI): void {
  let ctx: ExtensionContext | undefined;
  let commit = "";
  let requestRender: (() => void) | undefined;
  let installed = false;

  const refreshCommit = (cwd: string): void => {
    try {
      commit = execSync("git rev-parse --short=12 HEAD", { cwd, stdio: ["ignore", "pipe", "ignore"] })
        .toString()
        .trim();
    } catch {
      commit = "";
    }
    requestRender?.();
  };

  pi.on("session_start", (_event, sessionCtx) => {
    ctx = sessionCtx;
    refreshCommit(sessionCtx.cwd);
    if (installed) return;
    installed = true;
    sessionCtx.ui.setFooter((tui, theme, footerData) => {
      requestRender = () => tui.requestRender();
      const unsubscribe = footerData.onBranchChange(() => refreshCommit(ctx?.cwd ?? sessionCtx.cwd));
      return {
        dispose() {
          unsubscribe();
        },
        invalidate() {},
        render: (renderWidth: number) => renderPowerline(renderWidth, theme, footerData, ctx, commit),
      };
    });
  });

  // Keep the closure's ctx (and thus model / usage / cost) current, and redraw.
  for (const event of ["model_select", "thinking_level_select", "turn_start", "turn_end", "message_end"] as const) {
    pi.on(event, (_e, eventCtx) => {
      ctx = eventCtx;
      requestRender?.();
    });
  }
}
