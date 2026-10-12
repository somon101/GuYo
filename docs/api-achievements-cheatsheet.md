# GuYo API — достижения (шпаргалка)

## Задание для ИИ (скопируйте целиком)
Сделай мне программу (веб-страницу) для управления достижениями моего приложения GuYo через его API.
Требования:
- На первом экране — одно поле «API-ключ» и кнопка «Подключиться». Ключ сохраняй в localStorage, чтобы не вводить снова; кнопка «Выйти» удаляет его.
- После подключения вызови `GET /me` (проверка ключа), затем `GET /achievements` и покажи все достижения карточками в их порядке: иконка, название, описание, условие (подпись типа из `GET /achievements/condition-types` + число), цвет, включено/выключено, сколько людей получили (`earned_count`).
- Можно: создать достижение, изменить любое поле, загрузить/убрать иконку (PNG/JPEG/WEBP до 5 МБ), удалить (с подтверждением: у людей, получивших его, оно тоже пропадёт; предложи вместо этого «выключить»), менять порядок перетаскиванием (`PUT /achievements/order`).
- Ошибки показывай текстом из поля `detail` ответа. 401 = неверный/отключённый ключ → вернуть на экран ввода ключа.
- Интерфейс на русском, аккуратный, удобный на телефоне.
Ниже полная документация API.

## Адрес и ключ
- Базовый адрес: `https://backend-production-cda3.up.railway.app/api/v1`
- Ключ создаётся в админке GuYo → «API-ключи» → «Создать ключ» (показывается один раз).
- Каждый запрос: заголовок `X-API-Key: <ключ>` (можно `Authorization: Bearer <ключ>`).
- CORS открыт: можно вызывать прямо из браузера.

## Объект «достижение»
```json
{
  "id": 12,
  "title": "Сто слов",
  "description": "Изучено 100 слов.",
  "icon_url": "https://backend-production-cda3.up.railway.app/media/achievements/icons/abc.png",
  "color": "#0EA5E9",
  "condition_type": "words_learned",
  "condition_value": 100,
  "enabled": true,
  "visibility": "visible",
  "show_before_unlock": true,
  "order": 3,
  "earned_count": 57
}
```
- `icon_url` — `null`, если иконки нет.
- `visibility`: `"visible"` (видно всегда) или `"hidden"` (скрытое).
- `show_before_unlock` (для скрытых): `true` — показывать «загадкой» до получения, `false` — не показывать совсем.
- `enabled: false` — достижение выключено (новым не выдаётся, у получивших остаётся).

## Типы условий (`condition_type`)
| id | что считается |
|---|---|
| `words_learned` | изучено слов |
| `phrases_opened` | открыто фраз |
| `mini_phrases_done` | пройдено мини-фраз |
| `lessons_completed` | пройдено уроков |
| `streak_days` | дней активности подряд |
| `points_earned` | набрано очков |
| `friends_added` | добавлено друзей |
| `quest_words_completed` | слов, пройденных в квестах |
Актуальный список с подписями: `GET /achievements/condition-types`.

## Методы
| Метод | Путь | Что делает |
|---|---|---|
| GET | `/me` | Проверка ключа: `{"name","scopes","key_prefix"}` |
| GET | `/achievements/condition-types` | `[{"id","label"}]` |
| GET | `/achievements` | Все достижения по порядку |
| GET | `/achievements/{id}` | Одно достижение |
| POST | `/achievements` | Создать (JSON, см. ниже) → 201 + объект |
| PATCH | `/achievements/{id}` | Изменить любые поля (JSON, только нужные) → объект |
| DELETE | `/achievements/{id}` | Удалить → 204 (у получивших тоже пропадёт) |
| PUT | `/achievements/{id}/icon` | Загрузить иконку: multipart, поле `icon` → объект |
| DELETE | `/achievements/{id}/icon` | Убрать иконку → объект |
| PUT | `/achievements/order` | Порядок: `{"ids":[5,2,9,...]}` → все по новому порядку |

### Создать
```json
POST /achievements
{
  "title": "Полиглот",
  "description": "Изучено 300 слов.",
  "condition_type": "words_learned",
  "condition_value": 300,
  "color": "#0EA5E9",
  "visibility": "visible",
  "show_before_unlock": true,
  "enabled": true
}
```
Обязательны: `title`, `description`, `condition_type`, `condition_value` (≥1). `color` — `#RRGGBB`. `order` можно не указывать — встанет в конец.

### Изменить
```json
PATCH /achievements/12
{ "title": "Сотня слов", "condition_value": 120, "enabled": false }
```

### Иконка (пример на JS)
```js
const fd = new FormData();
fd.append("icon", file);              // File из <input type="file">
await fetch(`${BASE}/achievements/${id}/icon`, { method: "PUT", headers: { "X-API-Key": KEY }, body: fd });
```
Однотонный фон картинки (например, чёрный у JPEG) сервер сам делает прозрачным; прозрачный PNG сохраняется как есть.

## Ошибки
| Код | Значение |
|---|---|
| 401 | Нет ключа, ключ неверный или отключён |
| 403 | У ключа нет доступа к достижениям |
| 404 | Достижение не найдено |
| 422 | Неверные данные (тип условия, цвет, пустое название, формат/размер иконки) — причина в `detail` |

## Примеры curl
```bash
KEY="guyo_..."; BASE="https://backend-production-cda3.up.railway.app/api/v1"
curl -H "X-API-Key: $KEY" $BASE/achievements
curl -X PATCH -H "X-API-Key: $KEY" -H "Content-Type: application/json" -d '{"enabled":false}' $BASE/achievements/12
curl -X PUT -H "X-API-Key: $KEY" -F "icon=@badge.png" $BASE/achievements/12/icon
```
