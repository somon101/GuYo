import axios from "axios";
import { useState, type FormEvent } from "react";
import { changeAdminPassword } from "../api/endpoints";

/** «Пароль» in the header: the admin changes their own password. */
export function ChangePasswordButton() {
  const [open, setOpen] = useState(false);
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [repeat, setRepeat] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState(false);

  function close() {
    setOpen(false);
    setCurrent("");
    setNext("");
    setRepeat("");
    setError(null);
    setDone(false);
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (next.length < 10) return setError("Новый пароль — не короче 10 символов");
    if (next !== repeat) return setError("Пароли не совпадают");
    setSaving(true);
    setError(null);
    try {
      await changeAdminPassword(current, next);
      setDone(true);
    } catch (err) {
      const detail = axios.isAxiosError(err) ? err.response?.data?.detail : null;
      setError(typeof detail === "string" ? detail : "Не удалось сменить пароль");
    } finally {
      setSaving(false);
    }
  }

  const input = "w-full field px-3 py-2 text-sm";

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="rounded-lg px-3 py-1.5 text-sm font-medium text-slate-600 hover:bg-[var(--fill)] hover:text-slate-900"
      >
        Пароль
      </button>
      {open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={close}>
          <form onSubmit={submit} onClick={(e) => e.stopPropagation()} className="card w-full max-w-sm space-y-3 p-5">
            <h2 className="text-lg font-semibold text-[var(--label)]">Сменить пароль</h2>
            {done ? (
              <>
                <p className="text-sm text-[var(--sys-green-ink)]">
                  Пароль изменён. Запишите его в надёжное место и обновите его в секретах GitHub и в файле копий на
                  компьютере.
                </p>
                <button type="button" onClick={close} className="w-full rounded-md bg-[var(--sys-blue)] px-4 py-2 text-sm font-medium text-white">
                  Готово
                </button>
              </>
            ) : (
              <>
                <input type="password" className={input} placeholder="Текущий пароль" value={current} onChange={(e) => setCurrent(e.target.value)} autoFocus />
                <input type="password" className={input} placeholder="Новый пароль (10+ символов)" value={next} onChange={(e) => setNext(e.target.value)} />
                <input type="password" className={input} placeholder="Повторите новый пароль" value={repeat} onChange={(e) => setRepeat(e.target.value)} />
                {error && <p className="text-sm text-[var(--sys-red-ink)]">{error}</p>}
                <div className="flex gap-2">
                  <button type="button" onClick={close} className="btn-tinted flex-1 rounded-md px-4 py-2 text-sm font-medium">
                    Отмена
                  </button>
                  <button
                    type="submit"
                    disabled={saving || !current || !next}
                    className="flex-1 rounded-md bg-[var(--sys-blue)] px-4 py-2 text-sm font-medium text-white disabled:opacity-60"
                  >
                    {saving ? "Сохранение…" : "Сменить"}
                  </button>
                </div>
              </>
            )}
          </form>
        </div>
      )}
    </>
  );
}
