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
