import axios from 'axios';
import { useEffect, useState } from 'react';
import { giftDiamonds, disableGiftDefinition, disableShopProduct, listGiftDefinitions, listShopProducts, saveGiftDefinition, saveShopProduct, type GiftAdmin, type ShopProductAdmin } from '../api/endpoints';

const field = 'field min-w-0 rounded-lg px-2 py-1.5 text-sm';
function errorMessage(e: unknown) { return axios.isAxiosError(e) ? (e.response?.data?.detail ?? e.message) : String(e); }

export function EconomyPage() {
  const [products, setProducts] = useState<ShopProductAdmin[]>([]);
  const [gifts, setGifts] = useState<GiftAdmin[]>([]);
  const [error, setError] = useState('');
  const reload = async () => { try { const [p, g] = await Promise.all([listShopProducts(), listGiftDefinitions()]); setProducts(p); setGifts(g); setError(''); } catch (e) { setError(errorMessage(e)); } };
  useEffect(() => { void reload(); }, []);
  const saveProduct = async (p: ShopProductAdmin) => { try { const {id, ...body} = p; await saveShopProduct(body, id); await reload(); } catch(e) { setError(errorMessage(e)); } };
  const saveGift = async (g: GiftAdmin) => { try { const {id, ...body} = g; await saveGiftDefinition(body, id); await reload(); } catch(e) { setError(errorMessage(e)); } };
  const createProduct = async () => { try { await saveShopProduct({sku:`item-${Date.now()}`,name:'Новый товар',description:'',item_type:'streak_freeze',quantity:1,price_diamonds:50,icon_key:'freeze',enabled:true,sort_order:0}); await reload(); } catch(e) { setError(errorMessage(e)); } };
  const createGift = async () => { try { await saveGiftDefinition({key:`gift-${Date.now()}`,name:'Новый подарок',description:'',icon_key:'gift',reward_min:5,reward_max:25,cooldown_days:1,requires_activity:true,enabled:true,sort_order:0}); await reload(); } catch(e) { setError(errorMessage(e)); } };
  const update = <T extends object>(items:T[], set:(x:T[])=>void, i:number, key:keyof T, value:unknown) => set(items.map((item,n)=>n===i?{...item,[key]:value}:item));
  return <main className="mx-auto max-w-5xl space-y-8">
    <header><h1 className="text-2xl font-bold">Бриллианты, подарки и магазин</h1><p className="mt-1 text-sm text-slate-500">Настройте товары, цены, количество предметов и диапазон наград подарков.</p></header>
    {error && <div className="rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</div>}
    <GiftToUser />
    <section className="card p-4"><div className="mb-4 flex items-center justify-between"><h2 className="text-lg font-semibold">Товары магазина</h2><button className="bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50 rounded-lg px-3 py-2 text-sm" onClick={()=>void createProduct()}>Добавить товар</button></div>
      <div className="space-y-3">{products.map((p,i)=><div key={p.id} className="grid gap-2 rounded-xl border border-slate-200 p-3 md:grid-cols-12">
        <input className={`${field} md:col-span-2`} value={p.name} aria-label="Название" onChange={e=>update(products,setProducts,i,'name',e.target.value)}/>
        <select className={`${field} md:col-span-2`} value={p.item_type} onChange={e=>update(products,setProducts,i,'item_type',e.target.value)}><option value="streak_freeze">Заморозок</option><option value="streak_merge">Объединитель серии</option></select>
        <input className={`${field} md:col-span-2`} type="number" min="1" value={p.quantity} aria-label="Количество" onChange={e=>update(products,setProducts,i,'quantity',Number(e.target.value))}/>
        <input className={`${field} md:col-span-2`} type="number" min="0" value={p.price_diamonds} aria-label="Цена в бриллиантах" onChange={e=>update(products,setProducts,i,'price_diamonds',Number(e.target.value))}/>
        <input className={`${field} md:col-span-2`} value={p.description} aria-label="Описание" onChange={e=>update(products,setProducts,i,'description',e.target.value)}/>
        <div className="flex gap-2 md:col-span-2"><button className="bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50 rounded-lg px-3 text-sm" onClick={()=>void saveProduct(p)}>Сохранить</button><button className="bg-slate-100 text-slate-700 hover:bg-slate-200 rounded-lg px-2 text-sm" onClick={async()=>{await disableShopProduct(p.id); await reload();}}>Скрыть</button></div>
      </div>)}</div>
    </section>
    <section className="card p-4"><div className="mb-4 flex items-center justify-between"><h2 className="text-lg font-semibold">Подарки</h2><button className="bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50 rounded-lg px-3 py-2 text-sm" onClick={()=>void createGift()}>Добавить подарок</button></div>
      <div className="space-y-3">{gifts.map((g,i)=><div key={g.id} className="grid gap-2 rounded-xl border border-slate-200 p-3 md:grid-cols-12">
        <input className={`${field} md:col-span-2`} value={g.name} aria-label="Название" onChange={e=>update(gifts,setGifts,i,'name',e.target.value)}/>
        <input className={`${field} md:col-span-2`} type="number" min="0" value={g.reward_min} aria-label="Минимум" onChange={e=>update(gifts,setGifts,i,'reward_min',Number(e.target.value))}/>
        <input className={`${field} md:col-span-2`} type="number" min="0" value={g.reward_max} aria-label="Максимум" onChange={e=>update(gifts,setGifts,i,'reward_max',Number(e.target.value))}/>
        <input className={`${field} md:col-span-2`} type="number" min="1" value={g.cooldown_days} aria-label="Интервал дней" onChange={e=>update(gifts,setGifts,i,'cooldown_days',Number(e.target.value))}/>
        <input className={`${field} md:col-span-2`} value={g.description} aria-label="Описание" onChange={e=>update(gifts,setGifts,i,'description',e.target.value)}/>
        <div className="flex gap-2 md:col-span-2"><button className="bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50 rounded-lg px-3 text-sm" onClick={()=>void saveGift(g)}>Сохранить</button><button className="bg-slate-100 text-slate-700 hover:bg-slate-200 rounded-lg px-2 text-sm" onClick={async()=>{await disableGiftDefinition(g.id); await reload();}}>Скрыть</button></div>
        <label className="text-xs text-slate-600 md:col-span-4"><input type="checkbox" checked={g.requires_activity} onChange={e=>update(gifts,setGifts,i,'requires_activity',e.target.checked)}/> Требовать занятие перед открытием</label>
        <label className="text-xs text-slate-600 md:col-span-3"><input type="checkbox" checked={g.enabled} onChange={e=>update(gifts,setGifts,i,'enabled',e.target.checked)}/> Доступен пользователям</label>
      </div>)}</div>
    </section>
  </main>;
}

/** Gives diamonds to one person by login or 9-digit ID. */
function GiftToUser() {
  const [user, setUser] = useState('');
  const [amount, setAmount] = useState(100);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState('');
  const [error, setError] = useState('');
  const send = async () => {
    if (!user.trim() || amount < 1) return;
    setBusy(true); setError(''); setResult('');
    try {
      const r = await giftDiamonds(user.trim(), amount, note);
      setResult(`${r.login}: +${r.amount} 💎, теперь ${r.diamonds}`);
      setNote('');
    } catch (e) { setError(errorMessage(e)); } finally { setBusy(false); }
  };
  return <section className="card p-4">
    <h2 className="mb-1 text-lg font-semibold">Подарить бриллианты</h2>
    <p className="mb-3 text-sm text-slate-500">Человек сразу получит бриллианты и уведомление о подарке.</p>
    <div className="flex flex-wrap items-center gap-2">
      <input className={`${field} w-48`} placeholder="Логин или ID" value={user} onChange={(e) => setUser(e.target.value)} />
      <input className={`${field} w-24`} type="number" min={1} max={100000} value={amount} onChange={(e) => setAmount(Math.max(1, Number(e.target.value) || 1))} />
      <input className={`${field} w-64`} placeholder="Заметка (необязательно)" value={note} onChange={(e) => setNote(e.target.value)} />
      <button className="bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50 rounded-lg px-3 py-2 text-sm" disabled={busy || !user.trim()} onClick={() => void send()}>{busy ? 'Отправляем…' : 'Подарить'}</button>
    </div>
    {result && <p className="mt-2 text-sm text-emerald-700">{result}</p>}
    {error && <p className="mt-2 text-sm text-red-700">{error}</p>}
  </section>;
}
