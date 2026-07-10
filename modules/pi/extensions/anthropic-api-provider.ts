import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import {
  type Api,
  type AssistantMessageEventStream,
  type Context,
  type Model,
  type SimpleStreamOptions,
  streamSimpleAnthropic,
} from "@earendil-works/pi-ai";
import type { ExtensionAPI, ProviderModelConfig } from "@earendil-works/pi-coding-agent";

// Anthropic direct API as a pi provider that makes fast-mode (`speed: "fast"`)
// work on EVERY pi code path, not just the main agent loop.
//
// Why an extension with a custom transport instead of models.json + a
// `before_provider_request` hook: that hook only fires on the main agent loop.
// Side-calls (Esc+Esc rewind branch summaries via agent.streamFn, and
// pi-smart-sessions via complete()) bypass it, so the virtual id
// `claude-opus-4-8[fast]` reaches the API verbatim and 404s. A provider-level
// `streamSimple` is invoked on ALL of those paths, so it can strip the `[fast]`
// suffix (sending the real id) and inject `speed: "fast"` uniformly.
//
// Injection seam: this pi-ai build routes `streamSimple` through
// `buildBaseOptions`, which drops `options.client` (so the documented
// proxy-client approach cannot reach the request) but preserves `options.onPayload`.
// `stream()` calls `onPayload(params)` right after `buildParams`, so returning
// `{ ...params, speed: "fast" }` from a composed `onPayload` is the reliable
// body seam. The `fast-mode` beta header is added here too, because model
// headers only reach the wire on the main path — injecting in the transport
// covers the side-call paths as well.

// Home-relative so it resolves on any host (e.g. Linux /home/d, not just macOS /Users/dh).
const ENV_FILE = join(homedir(), ".files/modules/claude/.env.ant");
const FAST_SUFFIX = "[fast]";
const FAST_MODE_BETA = "fast-mode-2026-02-01";
const FINE_GRAINED_TOOL_STREAMING_BETA = "fine-grained-tool-streaming-2025-05-14";
const ANTHROPIC_BETA_HEADER = "anthropic-beta";
const FAST_BETAS = [FINE_GRAINED_TOOL_STREAMING_BETA, FAST_MODE_BETA];

const GEN5_THINKING_LEVEL_MAP: NonNullable<ProviderModelConfig["thinkingLevelMap"]> = {
  off: null,
  minimal: "low",
  low: "low",
  medium: "medium",
  high: "high",
  xhigh: "xhigh",
};

// Cost in USD per MILLION tokens — pi's own unit: calculateCost() computes
// `model.cost.<field> / 1_000_000 * tokens`, so these are raw per-Mtok dollars,
// NOT per token (the ProviderModelConfig "per token" doc comment is misleading).
// cacheWrite is the 5-minute rate; pi bills 1h writes at 2× input internally.
//
// Values are copied verbatim from pi-ai's built-in `ANTHROPIC_MODELS`
// (@earendil-works/pi-ai/providers/anthropic.models). That module can't be
// imported here: pi's extension loader aliases only the pi-ai root/compat/oauth
// (exact-match), the subpath is not aliased, no aliased entry re-exports the
// catalog, and createModels() is empty until the coding-agent wires providers in.
// So mirror it, keyed by model id — re-check when bumping a model version.
type Cost = ProviderModelConfig["cost"];
const COST: Record<"opus" | "sonnet" | "haiku" | "fable", Cost> = {
  opus: { input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25 },
  sonnet: { input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5 },
  haiku: { input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25 },
  fable: { input: 10, output: 50, cacheRead: 1, cacheWrite: 12.5 },
};

type OnPayload = NonNullable<SimpleStreamOptions["onPayload"]>;
type AnthropicModel = Model<"anthropic-messages">;

/**
 * Delegates to pi's built-in Anthropic Messages transport. The registry hands
 * back a broad `Model<Api>`; this provider only ever registers
 * `anthropic-messages` models, so narrowing to the concrete api is sound.
 */
function delegate(
  model: Model<Api>,
  context: Context,
  options?: SimpleStreamOptions,
): AssistantMessageEventStream {
  return streamSimpleAnthropic(model as AnthropicModel, context, options);
}

/** Reads simple KEY=value pairs (optional `export`, optional quotes) from an env file. */
function readEnvFile(path: string): Record<string, string> {
  const vars: Record<string, string> = {};
  let raw: string;
  try {
    raw = readFileSync(path, "utf8");
  } catch {
    return vars;
  }
  for (const line of raw.split("\n")) {
    // Optional `export`, an uppercase var name, then the value to end of line.
    const match = line.match(/^(?:export\s+)?([A-Z0-9_]+)=(.*)$/);
    if (match) vars[match[1]] = match[2].trim().replace(/^["']|["']$/g, "");
  }
  return vars;
}

/** True when the given pi model id is the virtual fast alias (ends in `[fast]`). */
function isFastId(modelId: string): boolean {
  return modelId.endsWith(FAST_SUFFIX);
}

/** Strips the `[fast]` suffix, yielding the real Anthropic model id. */
function stripFastSuffix(modelId: string): string {
  return modelId.slice(0, -FAST_SUFFIX.length);
}

/**
 * Returns headers that guarantee the fast-mode beta (plus fine-grained tool
 * streaming) is present, merged into any existing `anthropic-beta` value so the
 * fine-grained beta that `createClient` would otherwise add is not clobbered.
 */
function withFastBetaHeaders(
  headers?: Record<string, string | null>,
): Record<string, string | null> {
  const result = { ...headers };
  const existingKey = Object.keys(result).find(
    (key) => key.toLowerCase() === ANTHROPIC_BETA_HEADER,
  );
  const existing = existingKey ? result[existingKey] : undefined;
  const betas =
    typeof existing === "string"
      ? existing.split(",").map((beta) => beta.trim()).filter(Boolean)
      : [];
  for (const beta of FAST_BETAS) {
    if (!betas.includes(beta)) betas.push(beta);
  }
  result[existingKey ?? ANTHROPIC_BETA_HEADER] = betas.join(",");
  return result;
}

/**
 * Composes an `onPayload` hook that adds `speed: "fast"` to the request body
 * while preserving any caller-supplied hook (e.g. `before_provider_request`).
 */
function withSpeedFast(original?: OnPayload): OnPayload {
  return async (payload, model) => {
    const base = (await original?.(payload, model)) ?? payload;
    return { ...(base as Record<string, unknown>), speed: "fast" };
  };
}

/**
 * Custom transport: fast ids stream the real model id with `speed: "fast"` and
 * the fast-mode beta; every other id is a faithful pass-through to the built-in
 * Anthropic Messages transport.
 */
function streamSimple(
  model: Model<Api>,
  context: Context,
  options?: SimpleStreamOptions,
): AssistantMessageEventStream {
  if (!isFastId(model.id)) {
    return delegate(model, context, options);
  }
  const realModel: Model<Api> = { ...model, id: stripFastSuffix(model.id) };
  return delegate(realModel, context, {
    ...options,
    headers: withFastBetaHeaders(options?.headers),
    onPayload: withSpeedFast(options?.onPayload),
  });
}

function opusModel(id: string): ProviderModelConfig {
  return {
    id,
    name: id.endsWith(FAST_SUFFIX) ? "Claude Opus 4.8 (fast)" : "Claude Opus 4.8",
    reasoning: true,
    input: ["text", "image"],
    cost: COST.opus,
    contextWindow: 1_000_000,
    maxTokens: 128_000,
    compat: { forceAdaptiveThinking: true },
    thinkingLevelMap: GEN5_THINKING_LEVEL_MAP,
  };
}

function gen5Model(id: string, name: string, cost: Cost): ProviderModelConfig {
  return {
    id,
    name,
    reasoning: true,
    input: ["text", "image"],
    cost,
    contextWindow: 1_000_000,
    maxTokens: 64_000,
    compat: { forceAdaptiveThinking: true },
    thinkingLevelMap: GEN5_THINKING_LEVEL_MAP,
  };
}

const MODELS: ProviderModelConfig[] = [
  opusModel("claude-opus-4-8"),
  opusModel(`claude-opus-4-8${FAST_SUFFIX}`),
  gen5Model("claude-sonnet-5", "Claude Sonnet 5", COST.sonnet),
  gen5Model("claude-fable-5", "Claude Fable 5", COST.fable),
  {
    id: "claude-haiku-4-5",
    name: "Claude Haiku 4.5",
    reasoning: true,
    input: ["text", "image"],
    cost: COST.haiku,
    contextWindow: 200_000,
    maxTokens: 64_000,
  },
];

export default function anthropicApiProvider(pi: ExtensionAPI): void {
  // Prefer the dedicated key file (mirrors claude::ant) so an ambient
  // ANTHROPIC_API_KEY meant for the built-in provider cannot shadow it.
  const apiKey = readEnvFile(ENV_FILE).ANTHROPIC_API_KEY ?? process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    console.error(
      `anthropic-api-provider: ANTHROPIC_API_KEY not set (${ENV_FILE} or env); not registered`,
    );
    return;
  }

  pi.registerProvider("anthropic-api", {
    name: "Anthropic (direct API, fast-mode)",
    baseUrl: "https://api.anthropic.com",
    apiKey,
    api: "anthropic-messages",
    models: MODELS,
    streamSimple,
  });
}
