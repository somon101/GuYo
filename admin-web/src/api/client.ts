import axios from "axios";

// Set VITE_API_URL at build time (see .env.production). Falls back to the
// local FastAPI dev server so `npm run dev` works out of the box.
export const API_URL = import.meta.env.VITE_API_URL ?? "http://127.0.0.1:8000";

export const api = axios.create({
  baseURL: API_URL,
});

const TOKEN_KEY = "guyo_admin_token";

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token);
}

export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY);
  clearApiCache();
}

// Repeat visits open instantly: a GET answered in the last 30 seconds is
// served from memory. Any save, delete or upload clears everything, so an
// edit is never shown stale.
const CACHE_MS = 30_000;
// Progress the pages poll (imports, AI translation) is always fetched fresh.
function isLive(url: string | undefined): boolean {
  return !!url && (url.includes("/import/") || url.startsWith("/admin/translation"));
}

const cache = new Map<string, { at: number; data: unknown; status: number; headers: unknown }>();

api.interceptors.request.use((config) => {
  const method = (config.method ?? "get").toLowerCase();
  if (method !== "get") {
    cache.clear();
    return config;
  }
  if (isLive(config.url)) return config;
  const key = `${config.url}?${JSON.stringify(config.params ?? {})}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_MS) {
    config.adapter = async () => ({ data: hit.data, status: hit.status, statusText: "OK", headers: hit.headers as never, config });
  }
  return config;
});

api.interceptors.response.use((response) => {
  const config = response.config;
  if ((config.method ?? "get").toLowerCase() === "get" && config.responseType !== "blob" && !isLive(config.url)) {
    const key = `${config.url}?${JSON.stringify(config.params ?? {})}`;
    if (!cache.has(key) || Date.now() - cache.get(key)!.at >= CACHE_MS) {
      cache.set(key, { at: Date.now(), data: response.data, status: response.status, headers: response.headers });
    }
  }
  return response;
});

/** Drops remembered answers (logout). */
export function clearApiCache(): void {
  cache.clear();
}

api.interceptors.request.use((config) => {
  const token = getToken();
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      clearToken();
      if (!window.location.hash.includes("/login")) {
        window.location.hash = "#/login";
      }
    }
    return Promise.reject(error);
  },
);
