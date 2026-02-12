/**
 * Local ASR Transcription Implementation
 *
 * Credits:
 *   - C Implementation: Salvatore Sanfilippo (antirez) (BSD-2-Clause)
 *     https://github.com/antirez/qwen-asr
 */

import { exec } from "node:child_process";
import { promisify } from "node:util";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import type { AudioTranscriptionRequest, AudioTranscriptionResult } from "../../types.js";

const execAsync = promisify(exec);

const DEFAULT_INSTALL_PATH = path.join(os.homedir(), ".openclaw", "local-asr");
const DEFAULT_MODEL = "qwen3-asr-0.6b";

export interface LocalAsrConfig {
  installPath?: string;
  model?: string;
  language?: string;
}

/**
 * Check if local ASR is installed
 */
export function isLocalAsrInstalled(config: LocalAsrConfig = {}): boolean {
  const installPath = config.installPath ?? DEFAULT_INSTALL_PATH;
  const model = config.model ?? DEFAULT_MODEL;

  const binaryPath = path.join(installPath, "qwen_asr");
  const modelPath = path.join(installPath, model);

  return fs.existsSync(binaryPath) && fs.existsSync(modelPath);
}

/**
 * Get the installation path for local ASR
 */
export function getLocalAsrInstallPath(): string {
  return DEFAULT_INSTALL_PATH;
}

/**
 * Transcribe audio using local qwen-asr binary
 */
export async function transcribeWithLocalAsr(
  req: AudioTranscriptionRequest,
  config: LocalAsrConfig = {},
): Promise<AudioTranscriptionResult> {
  const installPath = config.installPath ?? DEFAULT_INSTALL_PATH;
  const model = config.model ?? req.model ?? DEFAULT_MODEL;
  const language = config.language ?? req.language;

  const binaryPath = path.join(installPath, "qwen_asr");
  const modelPath = path.join(installPath, model);

  // Check installation
  if (!fs.existsSync(binaryPath)) {
    throw new Error(
      `Local ASR not installed. Run: openclaw local-asr install\n` +
        `Expected binary at: ${binaryPath}`,
    );
  }

  if (!fs.existsSync(modelPath)) {
    throw new Error(
      `Local ASR model not found: ${model}\n` +
        `Expected at: ${modelPath}\n` +
        `Run: openclaw local-asr install`,
    );
  }

  // Create temp files
  const tmpDir = os.tmpdir();
  const timestamp = Date.now();
  const inputPath = path.join(tmpDir, `openclaw_asr_input_${timestamp}.bin`);
  const wavPath = path.join(tmpDir, `openclaw_asr_${timestamp}.wav`);

  try {
    // Write audio buffer to temp file
    fs.writeFileSync(inputPath, req.buffer);

    // Convert to 16kHz mono WAV using ffmpeg
    const ffmpegCmd = `ffmpeg -y -i "${inputPath}" -ar 16000 -ac 1 "${wavPath}" 2>/dev/null`;
    await execAsync(ffmpegCmd, { timeout: 30_000 });

    // Build qwen_asr command
    const args = [
      "-d",
      `"${modelPath}"`,
      "-i",
      `"${wavPath}"`,
      "--silent",
    ];

    if (language) {
      args.push("--language", language);
    }

    if (req.prompt) {
      args.push("--prompt", `"${req.prompt}"`);
    }

    const cmd = `"${binaryPath}" ${args.join(" ")}`;

    // Run transcription
    const { stdout } = await execAsync(cmd, { timeout: req.timeoutMs });

    return {
      text: stdout.trim(),
      model: model,
    };
  } finally {
    // Cleanup temp files
    try {
      if (fs.existsSync(inputPath)) fs.unlinkSync(inputPath);
      if (fs.existsSync(wavPath)) fs.unlinkSync(wavPath);
    } catch {
      // Ignore cleanup errors
    }
  }
}
