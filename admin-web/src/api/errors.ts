import axios from "axios";

/** The server's own message (`detail`) when there is one, else `fallback`. */
export function errorText(e: unknown, fallback: string): string {
  if (axios.isAxiosError(e) && typeof e.response?.data?.detail === "string") return e.response.data.detail;
  return fallback;
}
