import { HashRouter, Navigate, Route, Routes } from "react-router-dom";
import { AuthProvider } from "./context/AuthContext";
import { ProtectedRoute } from "./components/ProtectedRoute";
import { Layout } from "./components/Layout";
import { LoginPage } from "./pages/LoginPage";
import { UsersPage } from "./pages/UsersPage";
import { DictionariesPage } from "./pages/DictionariesPage";
import { DictionaryDetailPage } from "./pages/DictionaryDetailPage";
import { WordsListPage } from "./pages/WordsListPage";
import { WordEditPage } from "./pages/WordEditPage";
import { PhraseCategoriesPage } from "./pages/PhraseCategoriesPage";
import { PhrasesListPage } from "./pages/PhrasesListPage";
import { PhraseEditPage } from "./pages/PhraseEditPage";
import { ExercisesPage } from "./pages/ExercisesPage";
import { TrueOrFalseSettingsPage } from "./pages/exercises/TrueOrFalseSettingsPage";
import { MatchingSettingsPage } from "./pages/exercises/MatchingSettingsPage";
import { BuildWordSettingsPage } from "./pages/exercises/BuildWordSettingsPage";

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
            path="/dictionaries/:id/words"
            element={
              <ProtectedRoute>
                <Layout>
                  <WordsListPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/dictionaries/:id/categories/:categoryId"
            element={
              <ProtectedRoute>
                <Layout>
                  <WordsListPage />
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
          <Route
            path="/dictionaries/:id/phrases"
            element={
              <ProtectedRoute>
                <Layout>
                  <PhraseCategoriesPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/dictionaries/:id/phrases/all"
            element={
              <ProtectedRoute>
                <Layout>
                  <PhrasesListPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/dictionaries/:id/phrases/categories/:categoryId"
            element={
              <ProtectedRoute>
                <Layout>
                  <PhrasesListPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/dictionaries/:dictId/phrases/:phraseId"
            element={
              <ProtectedRoute>
                <Layout>
                  <PhraseEditPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/exercises"
            element={
              <ProtectedRoute>
                <Layout>
                  <ExercisesPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/exercises/true_or_false"
            element={
              <ProtectedRoute>
                <Layout>
                  <TrueOrFalseSettingsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/exercises/matching"
            element={
              <ProtectedRoute>
                <Layout>
                  <MatchingSettingsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/exercises/build_word"
            element={
              <ProtectedRoute>
                <Layout>
                  <BuildWordSettingsPage />
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
