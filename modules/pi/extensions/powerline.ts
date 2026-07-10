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
// Replaces the default two-line footer with a richer, coloured status block:
//
//   claude-opus-4-8[fast]  📁 <cwd> @ <host>  │  🌿 <branch> <commit>
//   <ctx-bar> NN%  │  ↑in ↓out R<read> W<write> ⚡hit%  │  $cost (sub)  │  ⏱ <elapsed>  ↺NN%
//   <extension statuses…>
//
// setFooter() replaces the ENTIRE built-in footer, so we re-render the
// extension-status line ourselves to keep contributions like "✓ fzf agents".
// Widgets (above/below the editor, e.g. the subagents "auto mode" hint) are
// unaffected.
//
// The context bar and the ↺ headroom number are two views of the same figure —
// pi only exposes context-window usage to extensions, so the bar tracks context
// used (fills up) and ↺ tracks context remaining (counts down). The screenshot
// this mimics paired the bar with a subscription block gauge, which pi does not
// surface; context usage is the honest, self-consistent substitute.

/** Truecolour accent palette, tuned to read against a dark theme. */
const PALETTE = {
  path: "#61afef", // blue
  host: "#c678dd", // purple
  branch: "#98c379", // green
  bar: "#d7af5f", // gold
  clock: "#56b6c2", // cyan
  danger: "#e06c75", // red
} as const;

const RESET = "\x1b[0m";
const BAR_CELLS = 10;
const CLOCK_TICK_MS = 60_000;

/** Emit a 24-bit foreground escape for a `#rrggbb` colour. */
function paint(hex: string, text: string): string {
  const n = Number.parseInt(hex.slice(1), 16);
  return `\x1b[38;2;${(n >> 16) & 255};${(n >> 8) & 255};${n & 255}m${text}${RESET}`;
}

/** Milliseconds → "50h 29m" / "29m" / "50h". */
function formatElapsed(ms: number): string {
  const totalMin = Math.max(0, Math.floor(ms / 60_000));
  const hours = Math.floor(totalMin / 60);
  const mins = totalMin % 60;
  if (hours <= 0) return `${mins}m`;
  if (mins === 0) return `${hours}h`;
  return `${hours}h ${mins}m`;
}

/** Wall-clock age of the session, from its first entry timestamp. */
function sessionElapsedMs(ctx: ExtensionContext): number {
  const entries = ctx.sessionManager.getEntries();
  const first = entries[0]?.timestamp;
  const start = first ? new Date(first).getTime() : Date.now();
  return Date.now() - start;
}

/** Rolled-up token/cost usage for the whole session. */
interface SessionUsage {
  cost: number;
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  /** Latest prompt's cache-hit rate (%), or null before any assistant reply. */
  hitRate: number | null;
}

/** Single walk over assistant messages, summing tokens and cost. */
function collectUsage(ctx: ExtensionContext): SessionUsage {
  const usage: SessionUsage = { cost: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, hitRate: null };
  for (const entry of ctx.sessionManager.getEntries()) {
    if (entry.type !== "message" || entry.message.role !== "assistant") continue;
    const u = entry.message.usage;
    usage.cost += u.cost.total;
    usage.input += u.input;
    usage.output += u.output;
    usage.cacheRead += u.cacheRead;
    usage.cacheWrite += u.cacheWrite;
    const prompt = u.input + u.cacheRead + u.cacheWrite;
    if (prompt > 0) usage.hitRate = (u.cacheRead / prompt) * 100;
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

/** Restyled token counters: dim labels, muted numbers, ⚡ cache-hit rate. */
function tokensGroup(theme: Theme, usage: SessionUsage): string {
  const label = (s: string) => theme.fg("dim", s);
  const num = (s: string) => theme.fg("muted", s);
  const parts = [`${label("↑")}${num(formatTokens(usage.input))}`, `${label("↓")}${num(formatTokens(usage.output))}`];
  if (usage.cacheRead) parts.push(`${label("R")}${num(formatTokens(usage.cacheRead))}`);
  if (usage.cacheWrite) parts.push(`${label("W")}${num(formatTokens(usage.cacheWrite))}`);
  if (usage.hitRate !== null) parts.push(`${label("⚡")}${num(`${usage.hitRate.toFixed(0)}%`)}`);
  return parts.join(" ");
}

/** Gold fuel-gauge for context usage; turns red past 90%. */
function contextBar(theme: Theme, percent: number | null): string {
  if (percent === null) return theme.fg("dim", "░".repeat(BAR_CELLS));
  const filled = Math.max(0, Math.min(BAR_CELLS, Math.round((percent / 100) * BAR_CELLS)));
  const colour = percent > 90 ? PALETTE.danger : PALETTE.bar;
  return paint(colour, "█".repeat(filled)) + theme.fg("dim", "░".repeat(BAR_CELLS - filled));
}

/** Context headroom, coloured by how little is left. */
function headroom(theme: Theme, percent: number | null): string {
  const glyph = theme.fg("dim", "↺");
  if (percent === null) return `${glyph}${theme.fg("dim", "?")}`;
  const remaining = Math.round(100 - percent);
  const label = `${remaining}%`;
  if (remaining < 10) return `${glyph}${theme.fg("error", label)}`;
  if (remaining < 25) return `${glyph}${theme.fg("warning", label)}`;
  return `${glyph}${theme.fg("muted", label)}`;
}

/** First line: model · folder@host · branch commit. */
function identityLine(theme: Theme, ctx: ExtensionContext, branch: string | null, commit: string): string {
  const sep = theme.fg("dim", "│");
  const model = theme.fg("dim", ctx.model?.id ?? "no-model");
  const folder = `📁 ${paint(PALETTE.path, basename(ctx.cwd) || ctx.cwd)}`;
  const host = `${theme.fg("dim", "@")} ${paint(PALETTE.host, hostname().split(".")[0])}`;
  let line = `${model} ${folder} ${host}`;
  if (branch) {
    const commitStr = commit ? ` ${theme.fg("dim", commit)}` : "";
    line += ` ${sep} 🌿 ${paint(PALETTE.branch, branch)}${commitStr}`;
  }
  return line;
}

/** Second line: context bar · tokens · cost · elapsed · headroom. */
function metricsLine(theme: Theme, ctx: ExtensionContext): string {
  const sep = theme.fg("dim", "│");
  const percent = ctx.getContextUsage()?.percent ?? null;
  const bar = contextBar(theme, percent);
  const pctText = theme.fg("text", percent === null ? "?%" : `${Math.round(percent)}%`);
  const usage = collectUsage(ctx);
  const tokens = tokensGroup(theme, usage);
  const onSub = ctx.model ? ctx.modelRegistry.isUsingOAuth(ctx.model) : false;
  const cost = paint(PALETTE.bar, formatCost(usage.cost)) + (onSub ? theme.fg("dim", " (sub)") : "");
  const clock = `⏱ ${paint(PALETTE.clock, formatElapsed(sessionElapsedMs(ctx)))}`;
  return `${bar} ${pctText} ${sep} ${tokens} ${sep} ${cost} ${sep} ${clock} ${headroom(theme, percent)}`;
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
  const lines = [identityLine(theme, ctx, branch, commit), metricsLine(theme, ctx)];
  const statuses = statusLine(footerData);
  if (statuses) lines.push(statuses);
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
      const timer = setInterval(() => tui.requestRender(), CLOCK_TICK_MS);
      return {
        dispose() {
          unsubscribe();
          clearInterval(timer);
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
