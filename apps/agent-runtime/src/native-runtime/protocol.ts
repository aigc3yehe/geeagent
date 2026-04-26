export type RuntimeRequest = {
  id: string;
  command: string;
  args?: string[];
};

export type RuntimeResponse = {
  id: string;
  ok: boolean;
  output?: string;
  error?: string;
};

export type RuntimeCommandContext = {
  configDir?: string;
};

export function okResponse(id: string, output: string): RuntimeResponse {
  return { id, ok: true, output };
}

export function errorResponse(id: string, error: unknown): RuntimeResponse {
  return {
    id,
    ok: false,
    error: error instanceof Error ? error.message : String(error),
  };
}
