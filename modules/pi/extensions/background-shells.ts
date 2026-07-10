import { type ChildProcess, spawn } from "node:child_process";
import { createWriteStream, mkdirSync, type WriteStream } from "node:fs";
import { join } from "node:path";
import { type ExtensionAPI, getAgentDir, getShellConfig, truncateTail } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

// Background shells for pi's bash tool.
//
// Overrides the built-in `bash` tool (registerTool with the same name reuses the
// built-in renderer) so we own the spawn and can DETACH-not-kill a command that
// outlives the auto-background threshold. Detached commands move into a module
// registry; the agent keeps control with the output-so-far and reads/stops them
// with the added `bash_output` / `kill_shell` tools.

/** Default seconds a foreground command may run before it is auto-backgrounded. */
const DEFAULT_BACKGROUND_AFTER_SECONDS = 300;
/** Per-call override env var (also disables auto-background when set to 0). */
const BACKGROUND_AFTER_ENV = "PI_BG_AFTER_SECONDS";
const MAX_OUTPUT_LINES = 2000;
const MAX_OUTPUT_BYTES = 50 * 1024;

type ShellStatus = "running" | "exited" | "killed";

/** A command whose combined output is kept in memory and mirrored to a log file. */
interface BackgroundShell {
  id: string;
  command: string;
  cwd: string;
  startedAt: number;
  child: ChildProcess;
  status: ShellStatus;
  exitCode: number | null;
  chunks: Buffer[];
  byteLength: number;
  outputFile: string;
  logStream: WriteStream | undefined;
  readCursor: number;
}

interface BashParams {
  command: string;
  timeout?: number;
  run_in_background?: boolean;
}

const shells = new Map<string, BackgroundShell>();
let counter = 0;
let shutdownHookInstalled = false;

/** Resolve the effective auto-background threshold in seconds (0 disables). */
function effectiveBackgroundAfterSeconds(): number {
  const raw = process.env[BACKGROUND_AFTER_ENV];
  if (raw !== undefined) {
    const parsed = Number(raw);
    if (Number.isFinite(parsed) && parsed >= 0) return parsed;
  }
  return DEFAULT_BACKGROUND_AFTER_SECONDS;
}

/** Kill a process and its whole group (cross-platform). */
function killProcessTree(pid: number): void {
  if (process.platform === "win32") {
    try {
      spawn("taskkill", ["/F", "/T", "/PID", String(pid)], { stdio: "ignore", detached: true, windowsHide: true });
    } catch {
      // taskkill unavailable; nothing else to try.
    }
    return;
  }
  try {
    process.kill(-pid, "SIGKILL");
  } catch {
    try {
      process.kill(pid, "SIGKILL");
    } catch {
      // Process already gone.
    }
  }
}

/** Directory that holds per-shell log files. */
function backgroundLogDir(): string {
  const dir = join(getAgentDir(), "background-shells");
  mkdirSync(dir, { recursive: true });
  return dir;
}

/** Kill all running shells; used on process exit and session shutdown. */
function killAllShells(): void {
  for (const shell of shells.values()) {
    if (shell.status === "running" && shell.child.pid) killProcessTree(shell.child.pid);
    try {
      shell.logStream?.end();
    } catch {
      // Stream already closed.
    }
  }
}

function installShutdownHook(): void {
  if (shutdownHookInstalled) return;
  shutdownHookInstalled = true;
  process.once("exit", killAllShells);
}

/** Spawn a command with the same stdio/detach semantics as the built-in bash tool. */
function spawnCommand(command: string, cwd: string): ChildProcess {
  const config = getShellConfig();
  const fromStdin = config.commandTransport === "stdin";
  const child = spawn(config.shell, fromStdin ? config.args : [...config.args, command], {
    cwd,
    detached: process.platform !== "win32",
    env: process.env,
    stdio: [fromStdin ? "pipe" : "ignore", "pipe", "pipe"],
    windowsHide: true,
  });
  if (fromStdin) {
    child.stdin?.on("error", () => {});
    child.stdin?.end(command);
  }
  return child;
}

function createShellState(command: string, cwd: string, child: ChildProcess): BackgroundShell {
  return {
    id: "",
    command,
    cwd,
    startedAt: Date.now(),
    child,
    status: "running",
    exitCode: null,
    chunks: [],
    byteLength: 0,
    outputFile: "",
    logStream: undefined,
    readCursor: 0,
  };
}

function appendChunk(shell: BackgroundShell, buf: Buffer): void {
  shell.chunks.push(buf);
  shell.byteLength += buf.length;
  shell.logStream?.write(buf);
}

/**
 * Resolve once the child has exited and both streams have drained.
 *
 * Draining before resolving ensures trailing output buffered in the pipe is
 * delivered to the data listeners before the command is reported as finished.
 */
function waitForExit(child: ChildProcess): Promise<number | null> {
  return new Promise((resolve) => {
    let exited = false;
    let code: number | null = null;
    let stdoutEnded = !child.stdout;
    let stderrEnded = !child.stderr;
    let done = false;
    const finish = () => {
      if (!done) {
        done = true;
        resolve(code);
      }
    };
    const maybe = () => {
      if (exited && stdoutEnded && stderrEnded) finish();
    };
    child.stdout?.once("end", () => {
      stdoutEnded = true;
      maybe();
    });
    child.stderr?.once("end", () => {
      stderrEnded = true;
      maybe();
    });
    child.once("exit", (c) => {
      exited = true;
      code = c;
      maybe();
    });
    child.once("close", (c) => {
      code = c ?? code;
      finish();
    });
    child.once("error", finish);
  });
}

/** Mark a shell exited (no-op once it is exited or killed). */
function markExited(shell: BackgroundShell, code: number | null): void {
  if (shell.status !== "running") return;
  shell.status = "exited";
  shell.exitCode = code;
  try {
    shell.logStream?.end();
  } catch {
    // Stream already closed.
  }
}

/** Kill a running shell and mark it killed. */
function killShell(shell: BackgroundShell): void {
  if (shell.child.pid) killProcessTree(shell.child.pid);
  shell.status = "killed";
  try {
    shell.logStream?.end();
  } catch {
    // Stream already closed.
  }
}

/**
 * Move a still-attached command into the background registry.
 *
 * Opens the log file, seeds it with the output captured so far, then routes
 * continued output to it. In-memory chunks remain the source of truth for reads.
 */
function finalizeAsBackground(shell: BackgroundShell, readFromStart: boolean, exitPromise: Promise<number | null>): void {
  installShutdownHook();
  shell.id = `bash_${++counter}`;
  shell.outputFile = join(backgroundLogDir(), `${shell.id}.log`);
  const stream = createWriteStream(shell.outputFile);
  if (shell.byteLength > 0) stream.write(Buffer.concat(shell.chunks));
  shell.logStream = stream;
  shell.readCursor = readFromStart ? 0 : shell.byteLength;
  shells.set(shell.id, shell);
  void exitPromise.then((code) => markExited(shell, code));
}

/** Truncate combined output for display, appending a note and log path when trimmed. */
function shapeOutput(shell: BackgroundShell): string {
  const raw = Buffer.concat(shell.chunks).toString("utf-8");
  const truncation = truncateTail(raw, { maxLines: MAX_OUTPUT_LINES, maxBytes: MAX_OUTPUT_BYTES });
  if (!truncation.truncated) return truncation.content;
  const startLine = truncation.totalLines - truncation.outputLines + 1;
  const where = shell.outputFile ? ` Full output: ${shell.outputFile}` : "";
  return `${truncation.content}\n\n[Showing lines ${startLine}-${truncation.totalLines} of ${truncation.totalLines} (truncated).${where}]`;
}

function foregroundResult(shell: BackgroundShell, code: number | null) {
  const text = shapeOutput(shell) || "(no output)";
  if (code !== 0 && code !== null) throw new Error(`${text}\n\nCommand exited with code ${code}`);
  return { content: [{ type: "text" as const, text }] };
}

function errorWithOutput(shell: BackgroundShell, status: string): Error {
  const text = shapeOutput(shell);
  return new Error(text ? `${text}\n\n${status}` : status);
}

function backgroundResult(shell: BackgroundShell, runInBackground: boolean) {
  const id = shell.id;
  if (runInBackground) {
    return {
      content: [
        {
          type: "text" as const,
          text: `Running in background as ${id}. Use bash_output(${id}) to read output, kill_shell(${id}) to stop.`,
        },
      ],
      details: { backgroundShellId: id },
    };
  }
  const shaped = shapeOutput(shell);
  const notice = `Command still running after ${effectiveBackgroundAfterSeconds()}s; backgrounded as ${id}. Read more with bash_output(${id}), stop with kill_shell(${id}).`;
  return {
    content: [{ type: "text" as const, text: shaped ? `${shaped}\n\n${notice}` : notice }],
    details: { backgroundShellId: id },
  };
}

/** Await either child exit or the auto-background timer (afterSeconds <= 0 disables it). */
async function raceExitOrBackground(
  exitPromise: Promise<number | null>,
  afterSeconds: number,
): Promise<"exit" | "background"> {
  if (afterSeconds <= 0) {
    await exitPromise;
    return "exit";
  }
  let timer: NodeJS.Timeout | undefined;
  try {
    return await Promise.race<"exit" | "background">([
      exitPromise.then(() => "exit" as const),
      new Promise<"background">((resolve) => {
        timer = setTimeout(() => resolve("background"), afterSeconds * 1000);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

/** Attach abort + hard-timeout handlers; returns a timeout flag reader and a disposer. */
function attachControls(child: ChildProcess, signal: AbortSignal | undefined, timeout: number | undefined) {
  let timedOut = false;
  let handle: NodeJS.Timeout | undefined;
  const onAbort = () => {
    if (child.pid) killProcessTree(child.pid);
  };
  if (timeout && timeout > 0) {
    handle = setTimeout(() => {
      timedOut = true;
      if (child.pid) killProcessTree(child.pid);
    }, timeout * 1000);
  }
  if (signal) {
    if (signal.aborted) onAbort();
    else signal.addEventListener("abort", onAbort, { once: true });
  }
  return {
    timedOut: () => timedOut,
    dispose: () => {
      if (handle) clearTimeout(handle);
      if (signal) signal.removeEventListener("abort", onAbort);
    },
  };
}

/** Execute a bash command, auto-backgrounding it if it outlives the threshold. */
async function runBash(params: BashParams, signal: AbortSignal | undefined, cwd: string) {
  const { command, timeout, run_in_background } = params;
  if (signal?.aborted) throw new Error("Command aborted");
  const child = spawnCommand(command, cwd);
  const shell = createShellState(command, cwd, child);
  const onData = (buf: Buffer) => appendChunk(shell, buf);
  child.stdout?.on("data", onData);
  child.stderr?.on("data", onData);
  const exitPromise = waitForExit(child);
  const controls = attachControls(child, signal, timeout);
  try {
    if (run_in_background) {
      finalizeAsBackground(shell, true, exitPromise);
      return backgroundResult(shell, true);
    }
    const outcome = await raceExitOrBackground(exitPromise, effectiveBackgroundAfterSeconds());
    if (signal?.aborted) throw errorWithOutput(shell, "Command aborted");
    if (outcome === "background") {
      finalizeAsBackground(shell, false, exitPromise);
      return backgroundResult(shell, false);
    }
    const code = await exitPromise;
    if (controls.timedOut()) throw errorWithOutput(shell, `Command timed out after ${timeout} seconds`);
    return foregroundResult(shell, code);
  } finally {
    controls.dispose();
  }
}

function describeStatus(shell: BackgroundShell): string {
  if (shell.status === "exited") return `[${shell.id} exited with code ${shell.exitCode ?? "unknown"}]`;
  if (shell.status === "killed") return `[${shell.id} was killed]`;
  return `[${shell.id} still running]`;
}

function applyFilter(text: string, filter: string): string {
  let regex: RegExp;
  try {
    regex = new RegExp(filter);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Invalid filter regular expression: ${reason}`);
  }
  return text
    .split("\n")
    .filter((line) => regex.test(line))
    .join("\n");
}

/** Read output produced since the last read and advance the cursor. */
function readNewOutput(shell: BackgroundShell): string {
  const full = Buffer.concat(shell.chunks);
  const fresh = full.subarray(shell.readCursor).toString("utf-8");
  shell.readCursor = shell.byteLength;
  return fresh;
}

const bashSchema = Type.Object({
  command: Type.String({ description: "Bash command to execute" }),
  timeout: Type.Optional(Type.Number({ description: "Hard timeout in seconds; kills the command when exceeded." })),
  run_in_background: Type.Optional(
    Type.Boolean({
      description:
        "Start the command detached in a background shell; returns a shell id immediately. Read output later with bash_output, stop it with kill_shell.",
    }),
  ),
});

const bashOutputSchema = Type.Object({
  shell_id: Type.String({ description: "Background shell id returned when a command was backgrounded (e.g. bash_1)." }),
  filter: Type.Optional(
    Type.String({ description: "Optional regular expression; only matching output lines are returned." }),
  ),
});

const killShellSchema = Type.Object({
  shell_id: Type.String({ description: "Background shell id to terminate (e.g. bash_1)." }),
});

/**
 * Register the bash override plus the bash_output / kill_shell tools.
 *
 * A bash command still running after the auto-background threshold (default 300s,
 * override via PI_BG_AFTER_SECONDS, 0 disables) is detached instead of killed.
 */
export default function backgroundShellsExtension(pi: ExtensionAPI): void {
  pi.registerTool({
    name: "bash",
    label: "bash",
    description: `Execute a bash command in the current working directory. Returns stdout and stderr (truncated to the last ${MAX_OUTPUT_LINES} lines or ${MAX_OUTPUT_BYTES / 1024}KB). A command still running after ${DEFAULT_BACKGROUND_AFTER_SECONDS}s is moved to a background shell (not killed): read its output with bash_output and stop it with kill_shell. Set run_in_background to detach immediately. Optionally provide a hard timeout in seconds.`,
    promptSnippet: "Execute bash commands; long ones auto-background (bash_output/kill_shell).",
    promptGuidelines: [
      "When bash reports a command was backgrounded, use bash_output(<id>) to read new output and kill_shell(<id>) to stop it.",
    ],
    parameters: bashSchema,
    async execute(_toolCallId, params: BashParams, signal, _onUpdate, ctx) {
      return runBash(params, signal, ctx.cwd);
    },
  });

  pi.registerTool({
    name: "bash_output",
    label: "bash_output",
    description:
      "Read new output (since the last read) from a background shell started by bash. Reports whether the shell is still running, has exited (with its code), or was killed. Optionally filter output lines with a regular expression.",
    promptSnippet: "Read new output from a background shell (see bash run_in_background).",
    parameters: bashOutputSchema,
    async execute(_toolCallId, params: { shell_id: string; filter?: string }) {
      const shell = shells.get(params.shell_id);
      if (!shell) {
        throw new Error(
          `Unknown background shell "${params.shell_id}". Use the id reported when a bash command was backgrounded.`,
        );
      }
      const fresh = readNewOutput(shell);
      const filtered = params.filter ? applyFilter(fresh, params.filter) : fresh;
      const trimmed = filtered.replace(/\n$/, "");
      const body = trimmed.length > 0 ? trimmed : "(no new output)";
      return {
        content: [{ type: "text" as const, text: `${body}\n\n${describeStatus(shell)}` }],
        details: { backgroundShellId: shell.id, status: shell.status },
      };
    },
  });

  pi.registerTool({
    name: "kill_shell",
    label: "kill_shell",
    description:
      "Stop a running background shell by id (kills its whole process tree). Use after bash reports a command was backgrounded, or to stop a run_in_background command.",
    promptSnippet: "Stop a background shell started by bash.",
    parameters: killShellSchema,
    async execute(_toolCallId, params: { shell_id: string }) {
      const shell = shells.get(params.shell_id);
      if (!shell) throw new Error(`Unknown background shell "${params.shell_id}".`);
      if (shell.status !== "running") {
        const code = shell.exitCode !== null ? `, exit code ${shell.exitCode}` : "";
        throw new Error(`Background shell "${params.shell_id}" is not running (already ${shell.status}${code}).`);
      }
      killShell(shell);
      return {
        content: [{ type: "text" as const, text: `Killed background shell ${params.shell_id}.` }],
        details: { backgroundShellId: params.shell_id, status: "killed" },
      };
    },
  });

  pi.on("session_shutdown", () => killAllShells());
}
