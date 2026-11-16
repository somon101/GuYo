/* Локальное хранилище: IndexedDB (проект и картинки), всё остаётся на устройстве. */
(function (root) {
  const AS = root.AS || (root.AS = {});
  const NAME = 'avatar-studio', VER = 1;
  let dbp = null;
  function open() {
    if (dbp) return dbp;
    dbp = new Promise((res, rej) => {
      if (!root.indexedDB) return rej(new Error('Хранилище недоступно'));
      const rq = indexedDB.open(NAME, VER);
      rq.onupgradeneeded = () => { const d = rq.result; if (!d.objectStoreNames.contains('kv')) d.createObjectStore('kv'); if (!d.objectStoreNames.contains('blobs')) d.createObjectStore('blobs'); };
      rq.onsuccess = () => res(rq.result);
      rq.onerror = () => rej(rq.error);
    });
    return dbp;
  }
  const tx = async (store, mode, fn) => {
    const d = await open();
    return new Promise((res, rej) => {
      const t = d.transaction(store, mode), r = fn(t.objectStore(store));
      t.oncomplete = () => res(r && r.result); t.onerror = () => rej(t.error); t.onabort = () => rej(t.error);
    });
  };
  AS.db = {
    get: (store, key) => tx(store, 'readonly', s => s.get(key)),
    put: (store, key, val) => tx(store, 'readwrite', s => s.put(val, key)),
    del: (store, key) => tx(store, 'readwrite', s => s.delete(key)),
    keys: store => tx(store, 'readonly', s => s.getAllKeys()),
    clear: store => tx(store, 'readwrite', s => s.clear()),
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
