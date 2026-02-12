/**
 * Local ASR Provider for OpenClaw
 *
 * Uses antirez's Pure C implementation of Qwen3-ASR for fast,
 * private, offline speech-to-text transcription.
 *
 * Credits:
 *   - Qwen3-ASR Model: Alibaba Qwen Team (Apache 2.0)
 *     https://github.com/QwenLM/Qwen3-ASR
 *   - C Implementation: Salvatore Sanfilippo (antirez) (BSD-2-Clause)
 *     https://github.com/antirez/qwen-asr
 *
 * @license MIT
 */

import type { MediaUnderstandingProvider, AudioTranscriptionRequest, AudioTranscriptionResult } from "../../types.js";
import { transcribeWithLocalAsr } from "./transcribe.js";

export const localAsrProvider: MediaUnderstandingProvider = {
  id: "local-asr",
  capabilities: ["audio"],
  transcribeAudio: async (req: AudioTranscriptionRequest): Promise<AudioTranscriptionResult> => {
    return transcribeWithLocalAsr(req);
  },
};
