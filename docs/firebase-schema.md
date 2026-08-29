# GoodLoop — schemat Firebase i plan uporządkowania

Stan: projekt na planie **Spark** (bez Cloud Functions). Cała logika zapisu
egzekwowana jest **regułami Firestore** — nie ma warstwy serwerowej.

## 1. Cele

- Jeden spójny schemat i nazewnictwo w całym Firestore.
- **Zamknięcie grywalizacji** — punktów / poziomu / osiągnięć / znajomości nie da się
  podrobić z poziomu aplikacji (walidacja regułami z `get()`).
- Podział feedu na **globalny** i **znajomi**.
- Przygotowanie pod **czat** (tylko między znajomymi).
- Ranking po punktach musi być wiarygodny.

## 2. Ograniczenia planu Spark

| Chcemy | Jak na Spark |
|---|---|
| Punkty nie do podrobienia | Reguła: `totalPoints_po == totalPoints_przed + get(global_tasks/$id).data.points` |
| Osiągnięcia nie do podrobienia | Reguła sprawdza próg (`completedTasks`, `streakDays`) dla odblokowywanego id |
| `early_bird` / `night_owl` | **Zostają na zaufaniu** — zależą od godziny wykonania zadania, której serwer nie zna |
| Znajomość wymaga zgody | Reguła: `friendships` można stworzyć tylko gdy `exists()` zaakceptowany `friend_request` |
| Ranking | `totalPoints` walidowany jw. → wiarygodny |

Koszt: kilka `get()`/`exists()` na akcję. Limit Spark 50k odczytów/dzień — dla małej
bazy użytkowników wystarcza.

## 3. Konwencje nazewnicze

Jedna pisownia wszędzie:

- `uid`, `displayName`, `photoUrl` (małe „url")
- Referencje do innego użytkownika (denormalizowane): `authorId` / `authorName` / `authorPhotoUrl`
- Timestampy: `createdAt`, `*At` (server timestamp)
- Koniec z: `photoURL`, `photoUrl`+`photoURL` mieszane, `userPhotoUrl`, `user1Photo`, `fromUserPhoto`, `user1Name`, `fromUserName`

Denormalizowane `authorName` / `authorPhotoUrl` **zostają** (tani odczyt). Akceptujemy,
że robią się nieaktualne po zmianie profilu — do ewentualnego odświeżania później.

## 4. Schemat kolekcji

### `users/{uid}`

```
uid: string
email: string
displayName: string
photoUrl: string | null
createdAt: timestamp
lastActive: timestamp

# grywalizacja — denormalizowane, walidowane regułą
completedTasks: int          # licznik
totalPoints: int
level: int                   # = f(totalPoints), pochodna
streakDays: int
completedTaskIds: string[]   # do filtra aktywnych zadań; ograniczone liczbą global_tasks
achievements: string[]       # tylko rośnie; progi sprawdzane regułą

# pola pomocnicze do walidacji ostatniego zapisu
lastCompletedTaskId: string        # id zadania z ostatniego completa (weryfikuje regułę)
lastUnlockedAchievement: string    # id ostatnio odblokowanego achievementu
lastTaskCompletedDate: timestamp
```

Bez podkolekcji `completed_tasks` (była martwa).

### `global_tasks/{taskId}`

```
title: string
description: string
category: string
difficulty: string
points: int
isActive: bool
createdAt: timestamp
```

Katalog zadań dnia. `allow write: if false` — edycja tylko z konsoli / Admin SDK.
Pole `text` (stara nazwa `title`) — do usunięcia z danych i z `TaskRepository.parseGlobalTask`.

### `feed/{postId}`

```
authorId: string
authorName: string
authorPhotoUrl: string | null
content: string (1..500)
imageUrl: string | null
taskId: string              # zadanie po którym powstał post
audience: 'global' | 'friends'
likesCount: int
likedBy: string[]
commentsCount: int
createdAt: timestamp
```

### `feed/{postId}/comments/{commentId}`

```
authorId, authorName, authorPhotoUrl
content: string (1..500)
createdAt: timestamp
```

### `friendships/{pairKey}`

`pairKey` = posortowane `"uidLo_uidHi"`. **Jeden dokument na parę.**

```
members: string[2]          # [uidLo, uidHi] — query: where('members','array-contains',myUid)
status: 'active' | 'blocked'
requestId: string           # friend_request z którego powstała (weryfikuje regułę)
createdAt: timestamp
```

Zastępuje `user1Id/user1Name/user1Photo/user2Id/...`. Jeden indeks zamiast dwóch.

### `friend_requests/{requestId}`

```
fromUserId: string
toUserId: string
status: 'pending' | 'accepted' | 'rejected'
createdAt: timestamp
respondedAt: timestamp | null
```

Bez denormalizowanych imion — dociągane z `users/{fromUserId}` przy wyświetlaniu listy.

### `conversations/{pairKey}` (czat, faza 5)

`pairKey` jak w `friendships`.

```
members: string[2]
lastMessage: string
lastMessageAt: timestamp
unread: map<uid, int>       # licznik nieprzeczytanych per użytkownik
createdAt: timestamp
```

### `conversations/{pairKey}/messages/{msgId}`

```
senderId: string
members: string[2]          # ZDENORMALIZOWANE z conversation — reguła read bez get()
text: string (1..2000)
createdAt: timestamp
```

## 5. Reguły — strategia

Pełny plik powstaje na branchu `feat/firestore-rules-lockdown`. Kluczowe fragmenty:

### Helpery

```
function isAuthenticated() { return request.auth != null; }
function isOwner(uid)      { return isAuthenticated() && request.auth.uid == uid; }
function pairKey(a, b)     { return a < b ? a + '_' + b : b + '_' + a; }
function changedKeys()     { return resource.data.diff(request.resource.data).affectedKeys(); }
```

### `users` — update rozbity na trzy dozwolone kształty

```
allow update: if isOwner(userId) && (
     isProfileUpdate()
  || isTaskCompletion()
  || isAchievementUnlock()
);

function isProfileUpdate() {
  return changedKeys().hasOnly(['displayName', 'photoUrl', 'lastActive']);
}

function isTaskCompletion() {
  let b = resource.data;
  let a = request.resource.data;
  let newId = a.lastCompletedTaskId;
  return changedKeys().hasOnly(['completedTaskIds','completedTasks','totalPoints',
                                'level','streakDays','lastCompletedTaskId',
                                'lastTaskCompletedDate','lastActive'])
    && !(newId in b.completedTaskIds)
    && (newId in a.completedTaskIds)
    && a.completedTaskIds.hasAll(b.completedTaskIds)
    && a.completedTaskIds.size() == b.completedTaskIds.size() + 1
    && a.completedTasks == b.completedTasks + 1
    && a.totalPoints == b.totalPoints
       + get(/databases/$(database)/documents/global_tasks/$(newId)).data.points
    && a.streakDays >= b.streakDays
    && a.streakDays <= b.streakDays + 1;
  // level: nie walidowane ściśle — wynika z totalPoints, które JEST. Ranking po punktach pewny.
}

function isAchievementUnlock() {
  let b = resource.data;
  let a = request.resource.data;
  let x = a.lastUnlockedAchievement;
  return changedKeys().hasOnly(['achievements','lastUnlockedAchievement','lastActive'])
    && a.achievements.hasAll(b.achievements)
    && a.achievements.size() == b.achievements.size() + 1
    && (x in a.achievements) && !(x in b.achievements)
    && achievementConditionMet(x, a);
}

function achievementConditionMet(id, u) {
  return (id == 'first_task'    && u.completedTasks >= 1)
      || (id == 'ten_tasks'     && u.completedTasks >= 10)
      || (id == 'fifty_tasks'   && u.completedTasks >= 50)
      || (id == 'hundred_tasks' && u.completedTasks >= 100)
      || (id == 'week_streak'   && u.streakDays >= 7)
      || id == 'early_bird'      // czasowe — zaufanie
      || id == 'night_owl';      // czasowe — zaufanie
}
```

**Konsekwencja dla kodu:** `TaskRepository.completeGlobalTask` musi w jednym `update`
ustawić `lastCompletedTaskId`, `completedTaskIds` (arrayUnion), `completedTasks`+1,
`totalPoints` +punkty zadania, `streakDays` (przeliczony), `lastTaskCompletedDate`.
`UserRepository.addAchievement` musi ustawiać `lastUnlockedAchievement` razem z `arrayUnion`.

### `feed`

```
allow read: if isAuthenticated() && (
     resource.data.audience == 'global'
  || resource.data.authorId == request.auth.uid
  || exists(/databases/$(database)/documents/friendships/$(pairKey(request.auth.uid, resource.data.authorId)))
);

allow create: if isAuthenticated()
  && request.resource.data.authorId == request.auth.uid
  && request.resource.data.content is string
  && request.resource.data.content.size() >= 1
  && request.resource.data.content.size() <= 500
  && request.resource.data.audience in ['global', 'friends'];

// autor → wszystko; nie-autor → tylko polubienie (jego uid ±1)
allow update: if isAuthenticated() && (
  resource.data.authorId == request.auth.uid
  || (
       changedKeys().hasOnly(['likedBy', 'likesCount'])
    && request.resource.data.likesCount == resource.data.likedBy.size() + (request.auth.uid in resource.data.likedBy ? -1 : 1) ... // uproszczenie — patrz implementacja
  )
);

allow delete: if isAuthenticated() && resource.data.authorId == request.auth.uid;
```

**Feed globalny:** `where('audience','==','global').orderBy('createdAt','desc')` — każdy
dok przechodzi regułę tanio (bez `exists()`).
**Feed znajomych:** `where('audience','==','friends').where('authorId','in', myFriendIds)` —
`exists()` na każdym wyniku (≈10–30 odczytów na załadowanie). Akceptowalne na Spark.

### `friendships`

```
allow read:   if isAuthenticated() && request.auth.uid in resource.data.members;
allow create: if isAuthenticated()
  && friendshipId == pairKey(request.resource.data.members[0], request.resource.data.members[1])
  && request.auth.uid in request.resource.data.members
  && request.resource.data.status == 'active'
  && exists(/databases/$(database)/documents/friend_requests/$(request.resource.data.requestId))
  && get(/databases/$(database)/documents/friend_requests/$(request.resource.data.requestId)).data.status == 'accepted';
allow update: if isAuthenticated() && request.auth.uid in resource.data.members
  && changedKeys().hasOnly(['status']);
allow delete: if isAuthenticated() && request.auth.uid in resource.data.members;
```

### `friend_requests`

```
allow read:   if isAuthenticated()
  && (resource.data.fromUserId == request.auth.uid || resource.data.toUserId == request.auth.uid);
allow create: if isAuthenticated()
  && request.resource.data.fromUserId == request.auth.uid
  && request.resource.data.fromUserId != request.resource.data.toUserId
  && request.resource.data.status == 'pending'
  && exists(/databases/$(database)/documents/users/$(request.resource.data.toUserId));
allow update: if isAuthenticated()
  && resource.data.toUserId == request.auth.uid
  && resource.data.status == 'pending'
  && request.resource.data.status in ['accepted', 'rejected']
  && changedKeys().hasOnly(['status', 'respondedAt']);
allow delete: if isAuthenticated()
  && (resource.data.fromUserId == request.auth.uid || resource.data.toUserId == request.auth.uid);
```

### `conversations` + `messages`

```
match /conversations/{convId} {
  allow read:   if isAuthenticated() && request.auth.uid in resource.data.members;
  allow create: if isAuthenticated()
    && convId == pairKey(request.resource.data.members[0], request.resource.data.members[1])
    && request.auth.uid in request.resource.data.members
    && exists(/databases/$(database)/documents/friendships/$(convId));
  allow update: if isAuthenticated() && request.auth.uid in resource.data.members;

  match /messages/{msgId} {
    allow read:   if isAuthenticated() && request.auth.uid in resource.data.members;
    allow create: if isAuthenticated()
      && request.resource.data.senderId == request.auth.uid
      && request.auth.uid in request.resource.data.members
      && request.resource.data.members == get(/databases/$(database)/documents/conversations/$(convId)).data.members
      && request.resource.data.text.size() >= 1
      && request.resource.data.text.size() <= 2000;
  }
}
```

### Usunąć z reguł

- `match /users/{userId}/completed_tasks/{taskId}` — martwa podkolekcja.
- `match /achievements/{achievementId}` — katalog przeniesiony do kodu (`AchievementModel.getAllAchievements`).

## 6. Migracja danych

Jednorazowy skrypt **lokalny** (Node + `firebase-admin`, klucz service account —
NIE commitować). Branch `chore/firestore-cleanup-script`, katalog `scripts/`.

Operacje:

1. **Usuń śmieci:**
   - `global_tasks` doc „TEST TASK FROM APP" (`MNReiHf4qKbuPXPgGVjF`)
   - testowe posty w `feed` (`content: "test"`), testowe komentarze
   - z `users/*/completedTaskIds` usuń id skasowanych zadań
2. **`users`:** `photoURL` → `photoUrl`; dodaj `lastCompletedTaskId: ''`, `lastUnlockedAchievement: ''` jeśli brak
3. **`feed`:** `userId`→`authorId`, `userName`→`authorName`, `userPhotoUrl`→`authorPhotoUrl`;
   dodaj `audience: 'global'` wszędzie gdzie brak; Appwrite URL (`cloud.appwrite.io`) → `null`
4. **`feed/*/comments`:** to samo `user*` → `author*`
5. **`friendships`:** dla każdego doc policz `pairKey`, ustaw `members: [lo, hi]`, `status`,
   przepisz do dokumentu o id = `pairKey`, usuń stary; wywal `user1Name/user1Photo/...`
6. **`friend_requests`:** usuń `fromUserName`, `fromUserPhoto` (dociągane w kliencie)

Skrypt idempotentny (można puścić 2×), z flagą `--dry-run`.

## 7. Plan wdrożenia (branche, po kolei)

| # | Branch | Zawartość |
|---|---|---|
| 1 | `fix/router-fallbacks` | (w toku) domknąć |
| 2 | `chore/firestore-cleanup-script` | skrypt migracyjny + `scripts/README`; **puścić `--dry-run`, sprawdzić, puścić na serio** |
| 3 | `refactor/firestore-schema` | `UserModel`/`*Repository` pod nowe nazwy pól, `lastCompletedTaskId`, przeliczanie `streakDays`, `feed`/`friendship` model |
| 4 | `feat/firestore-rules-lockdown` | nowy `firestore.rules` + walidacja anty-cheat; deploy `firebase deploy --only firestore:rules,firestore:indexes` |
| 5 | `feat/chat` | `conversations` + `messages`, UI czatu |

Kolejność 3 → 4 jest istotna: reguły wymagają `lastCompletedTaskId` i dokładnej matematyki
punktów, więc kod musi to wysyłać **zanim** reguły wejdą.

## 8. Znane kompromisy

- `early_bird` / `night_owl` — podrabialne (czasowe). Świadomie.
- `level` — nie walidowany ściśle; wynika z `totalPoints` (walidowane). Ranking po punktach pewny.
- Denormalizowane `authorName` / `authorPhotoUrl` — nieaktualne po zmianie profilu.
- Feed znajomych — `exists()` per wynik; przy dużej skali trzeba by przejść na Blaze + fan-out.
- Brak transakcyjności między `friend_request.status='accepted'` a utworzeniem `friendships`
  — okno, w którym request jest zaakceptowany a friendship jeszcze nie istnieje. Klient
  robi oba zapisy po sobie; w razie przerwania — retry przy następnym otwarciu listy znajomych.
- `likesCount` / `commentsCount` — liczniki utrzymywane po stronie klienta, mogą się
  rozjechać z `likedBy` / podkolekcją. Reguła pilnuje `likesCount == likedBy.size()`.
