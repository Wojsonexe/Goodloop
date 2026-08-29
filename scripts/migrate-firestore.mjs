/**
 * GoodLoop — jednorazowa migracja/porządkowanie Firestore.
 * Zgodnie z docs/firebase-schema.md.
 *
 * URUCHOMIENIE
 *   cd scripts && npm install
 *   export GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json
 *   node migrate-firestore.mjs                 # DRY-RUN — tylko wypisuje co by zrobił
 *   node migrate-firestore.mjs --commit        # faktyczny zapis
 *   node migrate-firestore.mjs --only=garbage,fields   # wybrane fazy
 *
 * FAZY: garbage | users | feed | friend_requests | friendships
 *
 * Skrypt jest idempotentny — można puścić wielokrotnie.
 * Klucz service account: Firebase Console → Ustawienia projektu → Konta usługi
 * → "Wygeneruj nowy klucz prywatny". NIE commitować (jest w .gitignore).
 */

import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

// ── KONFIG — uzupełnij o to co wiesz że jest śmieciem ───────────────────────
const GARBAGE_TASK_IDS = [
  'MNReiHf4qKbuPXPgGVjF', // "TEST TASK FROM APP" / "Created from debug button"
];
const GARBAGE_FEED_IDS = [
  'UE85mXFkutzyrRy7YB8M', // content: "test"
];
// Posty w feed, których content pasuje do wzorca — usuwane razem z komentarzami.
const GARBAGE_FEED_CONTENT = [/^test$/i, /^\s*$/];
const APPWRITE_MARKER = 'cloud.appwrite.io';
// Po wyczyszczeniu tablic — przelicz completedTasks/totalPoints/level z realnych zadań.
const RECALC_USER_STATS = true;
const LEVEL = (points) => Math.floor(points / 100) + 1;
// ───────────────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
const COMMIT = args.includes('--commit');
const onlyArg = args.find((a) => a.startsWith('--only='));
const PHASES = onlyArg
  ? onlyArg.slice('--only='.length).split(',')
  : ['garbage', 'users', 'feed', 'friend_requests', 'friendships'];

initializeApp({ credential: applicationDefault() });
const db = getFirestore();

let planned = 0;
const tag = COMMIT ? '[WRITE]' : '[dry-run]';
const log = (...m) => console.log(tag, ...m);

/** Zbiorczy zapis w porcjach po 400. */
function makeBatcher() {
  let batch = db.batch();
  let n = 0;
  const ops = [];
  return {
    set: (ref, data, opts) => { ops.push(['set', ref, data, opts]); },
    update: (ref, data) => { ops.push(['update', ref, data]); },
    delete: (ref) => { ops.push(['delete', ref]); },
    async flush() {
      planned += ops.length;
      if (!COMMIT) { ops.length = 0; return; }
      for (const op of ops) {
        if (op[0] === 'set') batch.set(op[1], op[2], op[3] ?? {});
        else if (op[0] === 'update') batch.update(op[1], op[2]);
        else batch.delete(op[1]);
        if (++n >= 400) { await batch.commit(); batch = db.batch(); n = 0; }
      }
      if (n > 0) { await batch.commit(); n = 0; }
      ops.length = 0;
    },
  };
}

/** Usuwa dokument wraz z podkolekcją comments (feed). */
async function deletePostDeep(b, docRef) {
  const comments = await docRef.collection('comments').get();
  comments.forEach((c) => { b.delete(c.ref); log('  del comment', docRef.id, '/', c.id); });
  b.delete(docRef);
}

// ── FAZA: garbage ──────────────────────────────────────────────────────────
async function phaseGarbage(b) {
  log('=== FAZA garbage ===');
  const deletedTaskIds = new Set();

  for (const id of GARBAGE_TASK_IDS) {
    const ref = db.collection('global_tasks').doc(id);
    if ((await ref.get()).exists) { b.delete(ref); deletedTaskIds.add(id); log('del global_tasks/' + id); }
  }

  const feed = await db.collection('feed').get();
  for (const doc of feed.docs) {
    const content = (doc.get('content') ?? '').toString();
    const isGarbage =
      GARBAGE_FEED_IDS.includes(doc.id) ||
      GARBAGE_FEED_CONTENT.some((re) => re.test(content));
    if (isGarbage) { log('del feed/' + doc.id, `(content: ${JSON.stringify(content)})`); await deletePostDeep(b, doc.ref); }
  }

  // Wyczyść skasowane id z users.completedTaskIds (+ ewentualny recalc).
  if (deletedTaskIds.size || RECALC_USER_STATS) {
    const taskPoints = await loadTaskPoints();
    const users = await db.collection('users').get();
    for (const u of users.docs) {
      const ids = Array.isArray(u.get('completedTaskIds')) ? u.get('completedTaskIds') : [];
      const kept = ids.filter((id) => !deletedTaskIds.has(id) && taskPoints.has(id));
      if (kept.length === ids.length && !RECALC_USER_STATS) continue;

      const patch = { completedTaskIds: kept };
      if (RECALC_USER_STATS) {
        const pts = kept.reduce((s, id) => s + (taskPoints.get(id) ?? 0), 0);
        patch.completedTasks = kept.length;
        patch.totalPoints = pts;
        patch.level = LEVEL(pts);
      }
      b.update(u.ref, patch);
      log('fix users/' + u.id, JSON.stringify(patch));
    }
  }
}

async function loadTaskPoints() {
  const snap = await db.collection('global_tasks').get();
  const m = new Map();
  snap.forEach((d) => m.set(d.id, Number(d.get('points') ?? 0)));
  // usuń świeżo skasowane śmieci z mapy
  GARBAGE_TASK_IDS.forEach((id) => m.delete(id));
  return m;
}

// ── FAZA: users ────────────────────────────────────────────────────────────
async function phaseUsers(b) {
  log('=== FAZA users ===');
  const users = await db.collection('users').get();
  for (const u of users.docs) {
    const d = u.data();
    const patch = {};
    if ('photoURL' in d && !('photoUrl' in d)) {
      patch.photoUrl = d.photoURL;
      patch.photoURL = FieldValue.delete();
    }
    if (!('lastCompletedTaskId' in d)) patch.lastCompletedTaskId = '';
    if (!('lastUnlockedAchievement' in d)) patch.lastUnlockedAchievement = '';
    if (Object.keys(patch).length) { b.update(u.ref, patch); log('users/' + u.id, Object.keys(patch).join(', ')); }
  }
}

// ── FAZA: feed (+comments) ─────────────────────────────────────────────────
function renameAuthorFields(d) {
  const patch = {};
  if ('userId' in d && !('authorId' in d)) { patch.authorId = d.userId; patch.userId = FieldValue.delete(); }
  if ('userName' in d && !('authorName' in d)) { patch.authorName = d.userName; patch.userName = FieldValue.delete(); }
  if ('userPhotoUrl' in d && !('authorPhotoUrl' in d)) {
    patch.authorPhotoUrl = d.userPhotoUrl; patch.userPhotoUrl = FieldValue.delete();
  }
  // Appwrite → null
  const photo = patch.authorPhotoUrl ?? d.authorPhotoUrl;
  if (typeof photo === 'string' && photo.includes(APPWRITE_MARKER)) patch.authorPhotoUrl = null;
  return patch;
}

async function phaseFeed(b) {
  log('=== FAZA feed ===');
  const feed = await db.collection('feed').get();
  for (const doc of feed.docs) {
    const d = doc.data();
    const patch = renameAuthorFields(d);
    if (!('audience' in d)) patch.audience = 'global';
    if (Object.keys(patch).length) { b.update(doc.ref, patch); log('feed/' + doc.id, Object.keys(patch).join(', ')); }

    const comments = await doc.ref.collection('comments').get();
    for (const c of comments.docs) {
      const cp = renameAuthorFields(c.data());
      if (Object.keys(cp).length) { b.update(c.ref, cp); log('  feed/' + doc.id + '/comments/' + c.id, Object.keys(cp).join(', ')); }
    }
  }
}

// ── FAZA: friend_requests ──────────────────────────────────────────────────
async function phaseFriendRequests(b) {
  log('=== FAZA friend_requests ===');
  const snap = await db.collection('friend_requests').get();
  for (const doc of snap.docs) {
    const d = doc.data();
    const patch = {};
    if ('fromUserName' in d) patch.fromUserName = FieldValue.delete();
    if ('fromUserPhoto' in d) patch.fromUserPhoto = FieldValue.delete();
    if (Object.keys(patch).length) { b.update(doc.ref, patch); log('friend_requests/' + doc.id, 'drop denorm'); }
  }
}

// ── FAZA: friendships → pairKey + members[] ────────────────────────────────
const pairKey = (a, b) => (a < b ? `${a}_${b}` : `${b}_${a}`);

async function phaseFriendships(b) {
  log('=== FAZA friendships ===');
  const snap = await db.collection('friendships').get();
  for (const doc of snap.docs) {
    const d = doc.data();
    const a = d.user1Id ?? (Array.isArray(d.members) ? d.members[0] : null);
    const c = d.user2Id ?? (Array.isArray(d.members) ? d.members[1] : null);
    if (!a || !c) { log('SKIP friendships/' + doc.id, '— brak user1Id/user2Id'); continue; }

    const key = pairKey(a, c);
    const members = a < c ? [a, c] : [c, a];
    const target = {
      members,
      status: d.status ?? 'active',
      requestId: d.requestId ?? 'migrated',
      createdAt: d.createdAt ?? FieldValue.serverTimestamp(),
    };

    const alreadyClean =
      doc.id === key &&
      Array.isArray(d.members) &&
      !('user1Id' in d) && !('user2Id' in d) &&
      !('user1Name' in d) && !('user2Name' in d);
    if (alreadyClean) { log('ok friendships/' + doc.id); continue; }

    b.set(db.collection('friendships').doc(key), target);
    log('set friendships/' + key, JSON.stringify(members));
    if (doc.id !== key) { b.delete(doc.ref); log('del friendships/' + doc.id, '(stary klucz)'); }
  }
}

// ── main ──────────────────────────────────────────────────────────────────
async function main() {
  console.log(`\nGoodLoop Firestore migration — ${COMMIT ? 'COMMIT (zapis!)' : 'DRY-RUN'}`);
  console.log('Fazy:', PHASES.join(', '), '\n');

  const b = makeBatcher();
  if (PHASES.includes('garbage')) { await phaseGarbage(b); await b.flush(); }
  if (PHASES.includes('users')) { await phaseUsers(b); await b.flush(); }
  if (PHASES.includes('feed')) { await phaseFeed(b); await b.flush(); }
  if (PHASES.includes('friend_requests')) { await phaseFriendRequests(b); await b.flush(); }
  if (PHASES.includes('friendships')) { await phaseFriendships(b); await b.flush(); }

  console.log(`\n${tag} operacji do wykonania: ${planned}`);
  if (!COMMIT) console.log('To był dry-run. Puść z --commit żeby zapisać.\n');
  else console.log('Zapisano.\n');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
