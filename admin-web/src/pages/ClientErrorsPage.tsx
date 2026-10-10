import { useEffect, useState } from "react";
import { listClientErrors, type ClientErrorRow } from "../api/endpoints";

/**
 * "Ошибки приложения": errors the mobile app caught on users' phones and
 * reported (see backend/app/routers/client_errors.py), newest first.
 */
export function ClientErrorsPage() {
  const [rows, setRows] = useState<ClientErrorRow[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [openId, setOpenId] = useState<number | null>(null);

  async function reload() {
    setIsLoading(true);
    setLoadError(null);
    try {
      setRows(await listClientErrors());
    } catch {
      setLoadError("Не удалось загрузить ошибки");
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    reload();
  }, []);

  return (
    <div className="p-6">
      <h1 className="mb-1 text-[26px] font-bold tracking-tight text-slate-900">Ошибки приложения</h1>
      <p className="mb-6 max-w-2xl text-sm text-slate-500">
        Сбои, которые приложение поймало на телефонах пользователей. Нажмите на строку, чтобы увидеть подробности.
      </p>
      <div className="mb-4">
        <button
          type="button"
          onClick={reload}
          className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          Обновить
        </button>
      </div>
      {isLoading ? (
        <p className="text-sm text-slate-500">Загрузка…</p>
      ) : loadError ? (
        <p className="text-sm text-red-600">{loadError}</p>
      ) : rows.length === 0 ? (
        <p className="text-sm text-slate-500">Ошибок нет</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {rows.map((e) => (
            <li key={e.id} className="card cursor-pointer p-4" onClick={() => setOpenId(openId === e.id ? null : e.id)}>
              <p className="break-words font-medium text-slate-900">{e.message}</p>
              <p className="mt-1 text-xs text-slate-500">
                {new Date(e.created_at).toLocaleString("ru-RU")} · {e.user_id ? `пользователь #${e.user_id}` : "без входа"}
                {e.app_build != null && ` · сборка ${e.app_build}`}
                {e.platform && ` · ${e.platform}`}
              </p>
              {openId === e.id && e.stack && (
                <pre className="mt-3 max-h-80 overflow-auto whitespace-pre-wrap rounded bg-slate-50 p-3 text-xs text-slate-700">
                  {e.stack}
                </pre>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
