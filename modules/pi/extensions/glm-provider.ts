import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// GLM 5.2 (llama.cpp, OpenAI-compatible) as a pi provider. Registered via an
// extension rather than models.json because baseUrl in models.json does not
// support env interpolation (only apiKey/headers do) and the tunnel URL rotates.
// Endpoint + key live in ~/.files/modules/pi/.env.glm; process env overrides.

const ENV_FILE = join(homedir(), ".files/modules/pi/.env.glm");

function readEnvFile(): Record<string, string> {
  const vars: Record<string, string> = {};
  let raw: string;
  try {
    raw = readFileSync(ENV_FILE, "utf8");
  } catch {
    return vars;
  }
  for (const line of raw.split("\n")) {
    const match = line.match(/^(?:export\s+)?([A-Z0-9_]+)=(.*)$/);
    if (match) vars[match[1]] = match[2].trim().replace(/^["']|["']$/g, "");
  }
  return vars;
}

export default function glmProvider(pi: ExtensionAPI) {
  const fileVars = readEnvFile();
  const baseUrl = process.env.GLM_BASE_URL ?? fileVars.GLM_BASE_URL;
  const apiKey = process.env.GLM_API_KEY ?? fileVars.GLM_API_KEY;
  if (!baseUrl || !apiKey) {
    console.error(`glm-provider: GLM_BASE_URL/GLM_API_KEY not set (env or ${ENV_FILE}); provider not registered`);
    return;
  }

  pi.registerProvider("glm", {
    name: "GLM (self-hosted)",
    baseUrl,
    apiKey,
    api: "openai-completions",
    models: [
      {
        id: "glm-5-2",
        name: "GLM 5.2 (llama.cpp)",
        reasoning: true,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        // llama.cpp /props reports n_ctx 262144 per slot for the loaded model.
        contextWindow: 262144,
        maxTokens: 8192,
        compat: {
          supportsDeveloperRole: false,
          supportsReasoningEffort: false,
          maxTokensField: "max_tokens",
          // GLM chat template reads chat_template_kwargs.enable_thinking;
          // bind it to pi's thinking toggle (off => direct answers).
          thinkingFormat: "chat-template",
          chatTemplateKwargs: { enable_thinking: { $var: "thinking.enabled" } },
        },
      },
    ],
  });
}
