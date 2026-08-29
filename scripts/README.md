# scripts/

Jednorazowe skrypty utrzymaniowe do bazy Firestore GoodLoop. Uruchamiane **lokalnie**
przez Admin SDK — nie są częścią aplikacji.

## `migrate-firestore.mjs`

Porządkuje Firestore zgodnie z [`../docs/firebase-schema.md`](../docs/firebase-schema.md):
usuwa śmieci testowe, ujednolica nazwy pól (`photoURL`→`photoUrl`, `user*`→`author*`),
przenosi `friendships` na klucz `pairKey` + `members[]`, czyści martwe URL-e z Appwrite.

### Wymagania

- Node 18+
- Klucz service account: **Firebase Console → Ustawienia projektu → Konta usługi →
  „Wygeneruj nowy klucz prywatny"**. Zapisz jako `scripts/serviceAccountKey.json`
  (jest w `.gitignore` — **nie commituj**).

### Użycie

```bash
cd scripts
npm install
export GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json

node migrate-firestore.mjs                      # DRY-RUN — wypisuje co by zrobił, nic nie zapisuje
node migrate-firestore.mjs --commit             # faktyczny zapis
node migrate-firestore.mjs --only=garbage       # tylko wybrana faza
node migrate-firestore.mjs --only=feed,users --commit
```

Fazy: `garbage`, `users`, `feed`, `friend_requests`, `friendships`.

### Zasady

1. **Zawsze najpierw dry-run.** Przejrzyj listę operacji.
2. Zrób eksport bazy przed `--commit` (Console → Firestore → Import/Export) — Spark
   nie ma automatycznego backupu.
3. Skrypt jest **idempotentny** — można puścić wielokrotnie.
4. Zanim puścisz — dopisz w `KONFIG` (góra pliku) id śmieci które znasz
   (`GARBAGE_TASK_IDS`, `GARBAGE_FEED_IDS`).

### Uwagi

- `RECALC_USER_STATS = true` → po wyczyszczeniu `completedTaskIds` przelicza
  `completedTasks` / `totalPoints` / `level` z realnie istniejących zadań. Testowym
  kontom wyzeruje nabite punkty — o to chodzi przy porządkach.
- Migrowane `friendships` dostają `requestId: 'migrated'` (brak historii requestu).
  Nowe reguły grandfatherują istniejące dokumenty (Admin SDK omija reguły).
- Renames pól w skrypcie muszą iść w parze ze zmianą `UserModel` / repozytoriów
  na branchu `refactor/firestore-schema` — patrz plan w `docs/firebase-schema.md §7`.
