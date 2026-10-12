import { useEffect, useState } from "react";
import { API_URL } from "../api/client";
import {
  createApiKey,
  deleteApiKey,
  listApiKeys,
  setApiKeyEnabled,
  type ApiKeyRow,
} from "../api/endpoints";

function when(value: string | null): string {
  return value
    ? new Date(value).toLocaleString("ru-RU", {
        dateStyle: "medium",
        timeStyle: "short",
      })
    : "—";
}

/** «API-ключи»: keys for the external API (/api/v1) -- today: achievements. */
export function ApiKeysPage() {
  const [keys, setKeys] = useState<ApiKeyRow[]>([]);
  const [name, setName] = useState("");
  const [fresh, setFresh] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function reload() {
    try {
      setKeys(await listApiKeys());
    } catch {
      setError("Не удалось загрузить ключи");
    }
  }

  useEffect(() => {
    reload();
  }, []);

  async function create() {
    if (!name.trim()) return;
    setBusy(true);
    setError(null);
    try {
      const created = await createApiKey(name.trim());
      setFresh(created.key);
      setCopied(false);
      setName("");
      reload();
    } catch {
      setError("Не удалось создать ключ");
    } finally {
      setBusy(false);
    }
  }

  async function copy() {
    if (!fresh) return;
    try {
      await navigator.clipboard.writeText(fresh);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  }

  const base = `${API_URL.replace(/\/$/, "")}/api/v1`;

  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="text-[26px] font-bold tracking-tight text-slate-900">
        API-ключи
      </h1>
      <p className="mb-6 mt-1 text-sm text-slate-500">
        Ключ даёт внешней программе доступ к API: смотреть, создавать, менять и
        удалять достижения (условия, иконки, порядок). Ключ начинает работать
        сразу. Отключённый ключ перестаёт работать мгновенно.
      </p>

      <div className="card mb-6 flex flex-col gap-3 p-4">
        <p className="font-medium text-slate-900">Создать ключ</p>
        <div className="flex flex-wrap gap-2">
          <input
            className="field min-w-[220px] flex-1 px-3 py-2 text-sm"
            placeholder="Название, например «Моя программа»"
            value={name}
            maxLength={120}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && create()}
          />
          <button
            onClick={create}
            disabled={busy || !name.trim()}
            className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
          >
            {busy ? "Создание…" : "Создать ключ"}
          </button>
        </div>
        {fresh && (
          <div className="rounded-lg border border-amber-300 bg-amber-50 p-3">
            <p className="mb-2 text-sm font-medium text-amber-900">
              Скопируйте ключ сейчас — больше он показан не будет.
            </p>
            <div className="flex flex-wrap items-center gap-2">
              <code className="flex-1 break-all rounded bg-white px-2 py-1.5 text-sm text-slate-900">
                {fresh}
              </code>
              <button
                onClick={copy}
                className="rounded-md bg-amber-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-amber-700"
              >
                {copied ? "Скопировано ✓" : "Скопировать"}
              </button>
            </div>
          </div>
        )}
        {error && <p className="text-sm text-red-600">{error}</p>}
      </div>

      <h2 className="mb-3 text-lg font-semibold text-slate-900">Ключи</h2>
      {keys.length === 0 ? (
        <p className="mb-6 text-sm text-slate-500">Ключей пока нет</p>
      ) : (
        <ul className="mb-6 flex flex-col gap-2">
          {keys.map((k) => (
            <li
              key={k.id}
              className="card flex flex-wrap items-center justify-between gap-3 p-3.5"
            >
              <div className="min-w-0">
                <p className="font-medium text-slate-900">
                  {k.name}
                  {!k.enabled && (
                    <span className="ml-2 text-xs text-slate-400">
                      отключён
                    </span>
                  )}
                </p>
                <p className="text-xs text-slate-500">
                  <code>{k.key_prefix}…</code> · создан {when(k.created_at)} ·
                  использован {when(k.last_used_at)}
                </p>
              </div>
              <div className="flex items-center gap-4">
                <label className="flex items-center gap-2 text-sm text-slate-600">
                  <input
                    type="checkbox"
                    className="switch"
                    checked={k.enabled}
                    onChange={async (e) => {
                      await setApiKeyEnabled(k.id, e.target.checked);
                      reload();
                    }}
                  />
                  {k.enabled ? "Работает" : "Отключён"}
                </label>
                <button
                  onClick={async () => {
                    if (
                      !confirm(
                        `Удалить ключ «${k.name}»? Программа с этим ключом перестанет работать.`,
                      )
                    )
                      return;
                    await deleteApiKey(k.id);
                    reload();
                  }}
                  className="text-sm text-slate-400 hover:text-red-600"
                >
                  Удалить
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}

      <div className="card p-4 text-sm text-slate-700">
        <p className="mb-2 font-medium text-slate-900">Как пользоваться</p>
        <p>
          Адрес API: <code className="break-all">{base}</code>
        </p>
        <p className="mt-1">
          Ключ передаётся в заголовке <code>X-API-Key</code>. Пример:
        </p>
        <pre className="mt-2 overflow-x-auto rounded bg-[var(--fill)] p-3 text-xs">{`curl -H "X-API-Key: ВАШ_КЛЮЧ" ${base}/achievements`}</pre>
        <p className="mt-2 text-slate-500">
          Методы: GET/POST <code>/achievements</code>, GET/PATCH/DELETE{" "}
          <code>/achievements/{"{id}"}</code>, PUT/DELETE{" "}
          <code>/achievements/{"{id}"}/icon</code>, PUT{" "}
          <code>/achievements/order</code>, GET{" "}
          <code>/achievements/condition-types</code>, GET <code>/me</code>.
        </p>
      </div>
    </div>
  );
}
