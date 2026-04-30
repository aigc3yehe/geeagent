import type { ModelFacingMessage } from "./types.js";

export function estimateTextTokens(text: string): number {
  let cjkChars = 0;
  let otherChars = 0;
  for (const ch of text) {
    if (/[\u3400-\u4dbf\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]/.test(ch)) {
      cjkChars += 1;
    } else {
      otherChars += 1;
    }
  }
  const charEstimate = cjkChars + Math.ceil(otherChars / 4);
  const byteEstimate = Math.ceil(Buffer.byteLength(text) / 4);
  return Math.max(1, charEstimate, byteEstimate);
}

export function estimateMessageTokens(message: ModelFacingMessage): number {
  return estimateTextTokens(message.role) + estimateTextTokens(message.content) + 8;
}

export function estimateMessagesTokens(messages: ModelFacingMessage[]): number {
  return messages.reduce((sum, message) => sum + estimateMessageTokens(message), 0);
}
