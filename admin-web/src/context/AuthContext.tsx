import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { adminLogin, fetchMe } from "../api/endpoints";
import { clearToken, getToken, setToken } from "../api/client";

interface AuthState {
  isAuthenticated: boolean;
  isLoading: boolean;
  login: (login: string, password: string) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthState | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const token = getToken();
    if (!token) {
      setIsLoading(false);
      return;
    }
    // Validate the stored token against the backend so a stale/expired
    // token doesn't silently look "logged in" after a page refresh.
    fetchMe()
      .then((me) => setIsAuthenticated(me.role === "admin"))
      .catch(() => clearToken())
      .finally(() => setIsLoading(false));
  }, []);

  async function login(loginValue: string, password: string) {
    const token = await adminLogin(loginValue, password);
    setToken(token);
    setIsAuthenticated(true);
  }

  function logout() {
    clearToken();
    setIsAuthenticated(false);
  }

  return (
    <AuthContext.Provider value={{ isAuthenticated, isLoading, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}
