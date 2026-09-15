import { HashRouter, Navigate, Route, Routes } from "react-router-dom";
import { AuthProvider } from "./context/AuthContext";
import { ProtectedRoute } from "./components/ProtectedRoute";
import { Layout } from "./components/Layout";
import { LoginPage } from "./pages/LoginPage";
import { UsersPage } from "./pages/UsersPage";
import { DictionariesPage } from "./pages/DictionariesPage";
import { DictionaryDetailPage } from "./pages/DictionaryDetailPage";
import { WordEditPage } from "./pages/WordEditPage";

// HashRouter is used deliberately: GitHub Pages serves static files with no
// server-side rewrites, so a BrowserRouter route like /dictionaries/3 would
// 404 on a hard refresh. Hash-based routes (#/dictionaries/3) always resolve
// to index.html first.
export default function App() {
  return (
    <AuthProvider>
      <HashRouter>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route
            path="/users"
            element={
              <ProtectedRoute>
                <Layout>
                  <UsersPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/dictionaries"
            element={
              <ProtectedRoute>
                <Layout>
                  <DictionariesPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/dictionaries/:id"
            element={
              <ProtectedRoute>
                <Layout>
                  <DictionaryDetailPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/dictionaries/:dictId/words/:wordId"
            element={
              <ProtectedRoute>
                <Layout>
                  <WordEditPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route path="/" element={<Navigate to="/users" replace />} />
          <Route path="*" element={<Navigate to="/users" replace />} />
        </Routes>
      </HashRouter>
    </AuthProvider>
  );
}
