import type {
  TelegramFileSendClient,
  TelegramLocalFileInput,
  TelegramSendClient,
  TelegramSendInput,
  TelegramSendResult,
} from "./send.js";
import { readFile } from "node:fs/promises";
import { basename } from "node:path";

type FetchResponseLike = {
  ok: boolean;
  status: number;
  json(): Promise<unknown>;
};

export type FetchLike = (
  url: string,
  init: {
    method: "POST";
    headers: Record<string, string>;
    body: string | FormData;
  },
) => Promise<FetchResponseLike>;

export type TelegramBotApiClientOptions = {
  apiBaseUrl?: string;
  fetch?: FetchLike;
};

export type TelegramGetUpdatesInput = {
  token: string;
  offset?: number;
  timeoutSeconds?: number;
};

export type TelegramGetUpdatesResult =
  | {
      ok: true;
      updates: unknown[];
    }
  | {
      ok: false;
      code: string;
      message: string;
      retryAfterMs?: number;
    };

type TelegramApiErrorPayload = {
  ok?: unknown;
  description?: unknown;
  parameters?: {
    retry_after?: unknown;
  };
};

type TelegramSendPayload = TelegramApiErrorPayload & {
  result?: {
    message_id?: unknown;
    date?: unknown;
  };
};

type TelegramAnyPayload = TelegramApiErrorPayload & {
  result?: unknown;
};

type TelegramApiFailureResult = {
  ok: false;
  code: string;
  message: string;
  retryAfterMs?: number;
};

export function createTelegramBotApiClient(
  options: TelegramBotApiClientOptions = {},
): TelegramSendClient & TelegramFileSendClient & {
  getUpdates(input: TelegramGetUpdatesInput): Promise<TelegramGetUpdatesResult>;
} {
  const apiBaseUrl = options.apiBaseUrl ?? "https://api.telegram.org";
  const fetchImpl = options.fetch ?? globalFetch;

  return {
    async sendMessage(input: TelegramSendInput): Promise<TelegramSendResult> {
      const url = `${apiBaseUrl}/bot${input.token}/sendMessage`;
      const body = messageBody(input);
      let response: FetchResponseLike;
      try {
        response = await fetchImpl(url, {
          method: "POST",
          headers: {
            "content-type": "application/json",
          },
          body: JSON.stringify(body),
        });
      } catch (error) {
        return {
          ok: false,
          code: "network_unavailable",
          message: sanitizeMessage(errorMessage(error), input.token),
        };
      }

      let payload: TelegramSendPayload = {};
      try {
        payload = (await response.json()) as TelegramSendPayload;
      } catch {
        payload = {};
      }

      if (response.ok && payload.ok === true) {
        const telegramMessageId = telegramMessageID(payload.result?.message_id);
        const sentAtSeconds = numberValue(payload.result?.date);
        if (!telegramMessageId || sentAtSeconds === undefined) {
          return {
            ok: false,
            code: "telegram_malformed_response",
            message: "Telegram sendMessage response did not include message_id and date.",
          };
        }
        return {
          ok: true,
          telegramMessageId,
          sentAt: telegramDate(sentAtSeconds),
        };
      }

      return apiFailure(response.status, payload, input.token);
    },
    async sendLocalFile(input: TelegramLocalFileInput): Promise<TelegramSendResult> {
      const upload = uploadEndpoint(input.filePath);
      const url = `${apiBaseUrl}/bot${input.token}/${upload.endpoint}`;
      const form = new FormData();
      form.set("chat_id", input.target.value);
      const caption = input.caption?.trim();
      if (caption) {
        form.set("caption", caption);
      }
      let fileData: Buffer;
      try {
        fileData = await readFile(input.filePath);
      } catch (error) {
        return {
          ok: false,
          code: "file_not_readable",
          message: sanitizeMessage(errorMessage(error), input.token),
        };
      }
      form.set(
        upload.fieldName,
        new Blob([new Uint8Array(fileData)], { type: mimeType(input.filePath) }),
        basename(input.filePath),
      );
      let response: FetchResponseLike;
      try {
        response = await fetchImpl(url, {
          method: "POST",
          headers: {},
          body: form,
        });
      } catch (error) {
        return {
          ok: false,
          code: "network_unavailable",
          message: sanitizeMessage(errorMessage(error), input.token),
        };
      }

      let payload: TelegramSendPayload = {};
      try {
        payload = (await response.json()) as TelegramSendPayload;
      } catch {
        payload = {};
      }

      if (response.ok && payload.ok === true) {
        const telegramMessageId = telegramMessageID(payload.result?.message_id);
        const sentAtSeconds = numberValue(payload.result?.date);
        if (!telegramMessageId || sentAtSeconds === undefined) {
          return {
            ok: false,
            code: "telegram_malformed_response",
            message: "Telegram file upload response did not include message_id and date.",
          };
        }
        return {
          ok: true,
          telegramMessageId,
          sentAt: telegramDate(sentAtSeconds),
        };
      }

      return apiFailure(response.status, payload, input.token);
    },
    async getUpdates(input: TelegramGetUpdatesInput): Promise<TelegramGetUpdatesResult> {
      const response = await botApiRequest(fetchImpl, apiBaseUrl, input.token, "getUpdates", {
        offset: input.offset,
        timeout: input.timeoutSeconds ?? 30,
        allowed_updates: ["message", "callback_query"],
      });
      if (response.status === "transport_error") {
        return response.error;
      }
      if (response.http.ok && response.payload.ok === true && Array.isArray(response.payload.result)) {
        return {
          ok: true,
          updates: response.payload.result,
        };
      }
      return apiFailure(response.http.status, response.payload, input.token);
    },
  };
}

async function botApiRequest(
  fetchImpl: FetchLike,
  apiBaseUrl: string,
  token: string,
  method: string,
  body: Record<string, unknown>,
): Promise<
  | {
      status: "received";
      http: FetchResponseLike;
      payload: TelegramAnyPayload;
    }
  | {
      status: "transport_error";
      error: {
        ok: false;
        code: string;
        message: string;
      };
    }
> {
  const url = `${apiBaseUrl}/bot${token}/${method}`;
  let response: FetchResponseLike;
  try {
    response = await fetchImpl(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
      },
      body: JSON.stringify(withoutUndefined(body)),
    });
  } catch (error) {
    return {
      status: "transport_error",
      error: {
        ok: false,
        code: "network_unavailable",
        message: sanitizeMessage(errorMessage(error), token),
      },
    };
  }
  let payload: TelegramAnyPayload = {};
  try {
    payload = (await response.json()) as TelegramAnyPayload;
  } catch {
    payload = {};
  }
  return {
    status: "received",
    http: response,
    payload,
  };
}

function messageBody(input: TelegramSendInput): Record<string, unknown> {
  const body: Record<string, unknown> = {
    chat_id: input.target.value,
    text: input.message,
  };
  if (input.parseMode) {
    body.parse_mode = input.parseMode;
  }
  if (typeof input.disableWebPreview === "boolean") {
    body.disable_web_page_preview = input.disableWebPreview;
  }
  return body;
}

function uploadEndpoint(filePath: string): { endpoint: string; fieldName: string } {
  switch (extension(filePath)) {
    case "jpg":
    case "jpeg":
    case "png":
    case "webp":
      return { endpoint: "sendPhoto", fieldName: "photo" };
    case "gif":
      return { endpoint: "sendAnimation", fieldName: "animation" };
    case "mp4":
    case "m4v":
    case "mov":
    case "webm":
      return { endpoint: "sendVideo", fieldName: "video" };
    default:
      return { endpoint: "sendDocument", fieldName: "document" };
  }
}

function mimeType(filePath: string): string {
  switch (extension(filePath)) {
    case "jpg":
    case "jpeg":
      return "image/jpeg";
    case "png":
      return "image/png";
    case "webp":
      return "image/webp";
    case "gif":
      return "image/gif";
    case "mp4":
    case "m4v":
      return "video/mp4";
    case "mov":
      return "video/quicktime";
    case "webm":
      return "video/webm";
    case "pdf":
      return "application/pdf";
    case "txt":
    case "log":
    case "md":
      return "text/plain";
    case "json":
      return "application/json";
    case "csv":
      return "text/csv";
    case "zip":
      return "application/zip";
    default:
      return "application/octet-stream";
  }
}

function extension(filePath: string): string {
  const index = filePath.lastIndexOf(".");
  return index >= 0 ? filePath.slice(index + 1).toLowerCase() : "";
}

function withoutUndefined(value: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined));
}

function apiFailure(
  status: number,
  payload: TelegramApiErrorPayload,
  token: string,
): TelegramApiFailureResult {
  const retryAfter = numberValue(payload.parameters?.retry_after);
  const description = sanitizeMessage(
    stringValue(payload.description) ?? `Telegram returned HTTP ${status}.`,
    token,
  );
  if (status === 429 || retryAfter !== undefined) {
    return {
      ok: false,
      code: "telegram_rate_limited",
      message: description,
      retryAfterMs: retryAfter === undefined ? undefined : retryAfter * 1000,
    };
  }
  return {
    ok: false,
    code: telegramErrorCode(status),
    message: description,
  };
}

function telegramErrorCode(status: number): string {
  switch (status) {
    case 400:
      return "telegram_bad_request";
    case 401:
      return "telegram_unauthorized";
    case 403:
      return "telegram_forbidden";
    default:
      return "telegram_api_error";
  }
}

function telegramDate(seconds: number): string {
  return new Date(seconds * 1000).toISOString();
}

function telegramMessageID(value: unknown): string | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    return String(value);
  }
  return stringValue(value);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function sanitizeMessage(message: string, token: string): string {
  return message.split(token).join("[redacted-token]");
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

async function globalFetch(
  url: string,
  init: {
    method: "POST";
    headers: Record<string, string>;
    body: string | FormData;
  },
): Promise<FetchResponseLike> {
  return fetch(url, init);
}
