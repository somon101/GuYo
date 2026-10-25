import { HashRouter, Navigate, Route, Routes } from "react-router-dom";
import { AuthProvider } from "./context/AuthContext";
import { ProtectedRoute } from "./components/ProtectedRoute";
import { Layout } from "./components/Layout";
import { LoginPage } from "./pages/LoginPage";
import { UsersPage } from "./pages/UsersPage";
import { StatusesPage } from "./pages/StatusesPage";
import { SlogansPage } from "./pages/SlogansPage";
import { ClientErrorsPage } from "./pages/ClientErrorsPage";
import { NotificationsPage } from "./pages/NotificationsPage";
import { PremiumPage } from "./pages/PremiumPage";
import { PromoPage } from "./pages/PromoPage";
import { DictionariesPage } from "./pages/DictionariesPage";
import { DictionaryDetailPage } from "./pages/DictionaryDetailPage";
import { WordsListPage } from "./pages/WordsListPage";
import { WordEditPage } from "./pages/WordEditPage";
import { PhraseCategoriesPage } from "./pages/PhraseCategoriesPage";
import { PhrasesListPage } from "./pages/PhrasesListPage";
import { PhraseEditPage } from "./pages/PhraseEditPage";
import { MiniPhrasesPage } from "./pages/MiniPhrasesPage";
import { MiniPhraseTemplatesPage } from "./pages/MiniPhraseTemplatesPage";
import { ContentAuditPage } from "./pages/ContentAuditPage";
import { MultilingualPage } from "./pages/MultilingualPage";
import { LanguageWordsPage } from "./pages/LanguageWordsPage";
import { LanguageWordPage } from "./pages/LanguageWordPage";
import { BasePage } from "./pages/BasePage";
import { ExercisesPage } from "./pages/ExercisesPage";
import { TrueOrFalseSettingsPage } from "./pages/exercises/TrueOrFalseSettingsPage";
import { MatchingSettingsPage } from "./pages/exercises/MatchingSettingsPage";
import { BuildWordSettingsPage } from "./pages/exercises/BuildWordSettingsPage";
import { SpeakingWordSettingsPage } from "./pages/exercises/SpeakingWordSettingsPage";
import { ListenWordSettingsPage } from "./pages/exercises/ListenWordSettingsPage";
import { WordLevelsSettingsPage } from "./pages/exercises/WordLevelsSettingsPage";
import { PrioritySettingsPage } from "./pages/PrioritySettingsPage";
import { QuestsPage } from "./pages/QuestsPage";
import { UserAnalyticsPage } from "./pages/UserAnalyticsPage";
import { RetentionPage } from "./pages/RetentionPage";
import { WordDiagnosticsPage } from "./pages/WordDiagnosticsPage";
import { MemoryWordPage } from "./pages/MemoryWordPage";
import { AchievementsPage } from "./pages/AchievementsPage";
import { ApiKeysPage } from "./pages/ApiKeysPage";
import { RatingPage } from "./pages/RatingPage";
import { SeasonPassPage } from "./pages/SeasonPassPage";
import { ReviewPage } from "./pages/ReviewPage";
import { AiToolsPage } from "./pages/AiToolsPage";
import { EconomyPage } from "./pages/EconomyPage";
import { ChestPreviewPage } from "./pages/ChestPreviewPage";
import { ChestsPage } from "./pages/ChestsPage";
import { DuelPreviewPage } from "./pages/DuelPreviewPage";
import { BoosterPreviewPage } from "./pages/BoosterPreviewPage";
import { PassPreviewPage } from "./pages/PassPreviewPage";
import { DailyGoalPreviewPage } from "./pages/DailyGoalPreviewPage";
import { AchievementPreviewPage } from "./pages/AchievementPreviewPage";

// HashRouter is used deliberately: GitHub Pages serves static files with no
// server-side rewrites, so a BrowserRouter route like /dictionaries/3 would
// 404 on a hard refresh. Hash-based routes (#/dictionaries/3) always resolve
// to index.html first.
//
// useTransitions={false}: route changes must commit synchronously so a link
// click can render the next screen inside a View Transition (see
// lib/pageTransitions.ts). Deferred, transition-wrapped updates would land
// after the browser already took the "new screen" snapshot.
export default function App() {
  return (
    <AuthProvider>
      <HashRouter useTransitions={false}>
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
            path="/dictionaries/:id/mini-phrases"
            element={
              <ProtectedRoute>
                <Layout>
                  <MiniPhrasesPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/multilingual"
            element={
              <ProtectedRoute>
                <Layout>
                  <MultilingualPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/base"
            element={
              <ProtectedRoute>
                <Layout>
                  <BasePage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/languages/:code/words/:entryId"
            element={
              <ProtectedRoute>
                <Layout>
                  <LanguageWordPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/languages/:code/words"
            element={
              <ProtectedRoute>
                <Layout>
                  <LanguageWordsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/dictionaries/:id/audit"
            element={
              <ProtectedRoute>
                <Layout>
                  <ContentAuditPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/mini-phrase-templates"
            element={
              <ProtectedRoute>
                <Layout>
                  <MiniPhraseTemplatesPage />
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
          <Route
            path="/exercises/speaking_word"
            element={
              <ProtectedRoute>
                <Layout>
                  <SpeakingWordSettingsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/exercises/listen_word"
            element={
              <ProtectedRoute>
                <Layout>
                  <ListenWordSettingsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/exercises/word-levels"
            element={
              <ProtectedRoute>
                <Layout>
                  <WordLevelsSettingsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/exercises/priority"
            element={
              <ProtectedRoute>
                <Layout>
                  <PrioritySettingsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/translation"
            element={
              <ProtectedRoute>
                <Layout>
                  <AiToolsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/quests"
            element={
              <ProtectedRoute>
                <Layout>
                  <QuestsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/slogans"
            element={
              <ProtectedRoute>
                <Layout>
                  <SlogansPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/client-errors"
            element={
              <ProtectedRoute>
                <Layout>
                  <ClientErrorsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/statuses"
            element={
              <ProtectedRoute>
                <Layout>
                  <StatusesPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/notifications"
            element={
              <ProtectedRoute>
                <Layout>
                  <NotificationsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/premium"
            element={
              <ProtectedRoute>
                <Layout>
                  <PremiumPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/promo"
            element={
              <ProtectedRoute>
                <Layout>
                  <PromoPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/retention"
            element={
              <ProtectedRoute>
                <Layout>
                  <RetentionPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/analytics"
            element={
              <ProtectedRoute>
                <Layout>
                  <UserAnalyticsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/analytics/users/:userId/memory/:wordId"
            element={
              <ProtectedRoute>
                <Layout>
                  <MemoryWordPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/analytics/users/:userId/words/:wordId"
            element={
              <ProtectedRoute>
                <Layout>
                  <WordDiagnosticsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/api-keys"
            element={
              <ProtectedRoute>
                <Layout>
                  <ApiKeysPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/achievements"
            element={
              <ProtectedRoute>
                <Layout>
                  <AchievementsPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/season-pass"
            element={
              <ProtectedRoute>
                <Layout>
                  <SeasonPassPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route path="/economy" element={<ProtectedRoute><Layout><EconomyPage /></Layout></ProtectedRoute>} />
          <Route path="/achievement-preview" element={<ProtectedRoute><Layout><AchievementPreviewPage /></Layout></ProtectedRoute>} />
          <Route path="/pass-preview" element={<ProtectedRoute><Layout><PassPreviewPage /></Layout></ProtectedRoute>} />
          <Route path="/daily-goal-preview" element={<ProtectedRoute><Layout><DailyGoalPreviewPage /></Layout></ProtectedRoute>} />
          <Route path="/booster-preview" element={<ProtectedRoute><Layout><BoosterPreviewPage /></Layout></ProtectedRoute>} />
          <Route path="/duel-preview" element={<ProtectedRoute><Layout><DuelPreviewPage /></Layout></ProtectedRoute>} />
          <Route path="/chests" element={<ProtectedRoute><Layout><ChestsPage /></Layout></ProtectedRoute>} />
          <Route path="/chest-preview" element={<ProtectedRoute><Layout><ChestPreviewPage /></Layout></ProtectedRoute>} />
          <Route
            path="/rating"
            element={
              <ProtectedRoute>
                <Layout>
                  <RatingPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          <Route
            path="/review"
            element={
              <ProtectedRoute>
                <Layout>
                  <ReviewPage />
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
