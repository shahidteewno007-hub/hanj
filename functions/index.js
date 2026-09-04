/**
 * Aruku — Firebase Cloud Functions
 * Handles all push notification triggers:
 *   - New season anime alerts     (scheduled, weekly)
 *   - Episode reminders           (scheduled, daily)
 *   - Weekly recap digest         (scheduled, Sunday)
 *   - Friend activity             (Firestore trigger)
 *   - Streak alerts               (scheduled, daily)
 *
 * Deploy:
 *   cd functions && npm install && firebase deploy --only functions
 */

const { onSchedule }        = require('firebase-functions/v2/scheduler');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret }      = require('firebase-functions/params');
const { initializeApp }     = require('firebase-admin/app');
const { getFirestore }      = require('firebase-admin/firestore');
const { getMessaging }      = require('firebase-admin/messaging');
const fetch                 = require('node-fetch');
const Anthropic             = require('@anthropic-ai/sdk');

initializeApp();

const db  = getFirestore();
const fcm = getMessaging();

const ANILIST_URL = 'https://graphql.anilist.co';

// Tomo (AI companion) — secret holds your Anthropic API key.
const ANTHROPIC_API_KEY = defineSecret('ANTHROPIC_API_KEY');

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

async function getUsersWithPref(prefKey) {
  const snap = await db.collection('users').get();
  return snap.docs.filter(doc => {
    const prefs = doc.data().notifPrefs ?? {};
    return prefs[prefKey] !== false; // default true if not set
  });
}

async function sendToUser(uid, payload) {
  const doc   = await db.collection('users').doc(uid).get();
  const token = doc.data()?.fcmToken;
  if (!token) return;

  try {
    await fcm.send({ token, ...payload });
  } catch (err) {
    // Token stale — remove it
    if (err.code === 'messaging/registration-token-not-registered') {
      await db.collection('users').doc(uid).update({ fcmToken: null });
    }
    console.error(`FCM error for ${uid}:`, err.message);
  }
}

async function anilistQuery(query, variables = {}) {
  const res = await fetch(ANILIST_URL, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify({ query, variables }),
  });
  return res.json();
}

function currentSeason() {
  const m = new Date().getMonth() + 1;
  if (m <= 3)  return 'WINTER';
  if (m <= 6)  return 'SPRING';
  if (m <= 9)  return 'SUMMER';
  return 'FALL';
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. New Season Alerts — runs 1st of each quarter
// ─────────────────────────────────────────────────────────────────────────────

exports.newSeasonAlert = onSchedule('0 9 1 1,4,7,10 *', async () => {
  const season = currentSeason();
  const year   = new Date().getFullYear();

  const data = await anilistQuery(`
    query($season: MediaSeason, $year: Int) {
      Page(page: 1, perPage: 5) {
        media(season: $season, seasonYear: $year, sort: POPULARITY_DESC, type: ANIME) {
          title { romaji }
          id
        }
      }
    }
  `, { season, year });

  const titles = data?.data?.Page?.media
    ?.map(m => m.title.romaji)
    ?.slice(0, 3)
    ?.join(', ') ?? 'new anime';

  const users = await getUsersWithPref('new_season');

  await Promise.allSettled(users.map(doc =>
    sendToUser(doc.id, {
      notification: {
        title: `${season.charAt(0) + season.slice(1).toLowerCase()} ${year} is here`,
        body:  `${titles} and more are now airing. Check what's new!`,
      },
      data: { type: 'new_season', season, year: String(year) },
      android: { notification: { channelId: 'aruku_general', color: '#E8624A' } },
      apns: { payload: { aps: { badge: 1 } } },
    })
  ));

  console.log(`New season alert sent to ${users.length} users`);
});

// ─────────────────────────────────────────────────────────────────────────────
// 2. Episode Reminders — runs daily at 10:00 UTC
//    Checks each user's WATCHING list against AniList airing schedule
// ─────────────────────────────────────────────────────────────────────────────

exports.episodeReminders = onSchedule('0 10 * * *', async () => {
  const users = await getUsersWithPref('episode_reminder');

  await Promise.allSettled(users.map(async doc => {
    const uid = doc.id;

    // Get user's WATCHING anime IDs
    const listSnap = await db
      .collection('users').doc(uid)
      .collection('animeList')
      .where('status', '==', 'WATCHING')
      .get();

    if (listSnap.empty) return;

    const ids = listSnap.docs.map(d => parseInt(d.data().animeId)).filter(Boolean);
    if (ids.length === 0) return;

    // Check AniList for episodes airing today
    const today   = Math.floor(Date.now() / 1000);
    const dayEnd  = today + 86400;

    const data = await anilistQuery(`
      query($ids: [Int]) {
        Page(page: 1, perPage: 50) {
          airingSchedules(mediaId_in: $ids, airingAt_greater: ${today}, airingAt_lesser: ${dayEnd}) {
            episode
            media {
              id
              title { romaji }
            }
          }
        }
      }
    `, { ids });

    const schedules = data?.data?.Page?.airingSchedules ?? [];
    if (schedules.length === 0) return;

    for (const s of schedules) {
      await sendToUser(uid, {
        notification: {
          title: s.media.title.romaji,
          body:  `Episode ${s.episode} is out now. Time to watch!`,
        },
        data: {
          type:    'episode_reminder',
          animeId: String(s.media.id),
          episode: String(s.episode),
        },
        android: { notification: { channelId: 'aruku_reminder', color: '#E8624A' } },
        apns: { payload: { aps: { badge: 1 } } },
      });
    }
  }));

  console.log('Episode reminder run complete');
});


// ─────────────────────────────────────────────────────────────────────────────
// 2b. Episode Reminder Precise — every 10 min
//    For users who tapped the bell on a specific anime in the app.
//    Notifies 15 min BEFORE the next episode airs.
//    Uses Firestore document at users/{uid}/alerts/{animeId}
//    Tracks fired notifications at users/{uid}/firedAlerts/{animeId_episode}
//    to avoid duplicate sends.
// ─────────────────────────────────────────────────────────────────────────────

exports.episodeReminderPrecise = onSchedule('*/10 * * * *', async () => {
  // Build map: animeId -> Set<uid> who alerted on it
  const alertedAnime = new Map();

  const usersSnap = await db.collection('users').get();
  await Promise.allSettled(usersSnap.docs.map(async userDoc => {
    const uid = userDoc.id;

    // Respect user's episode_reminder pref
    const prefs = userDoc.data().notifPrefs ?? {};
    if (prefs.episode_reminder === false) return;

    const alertsSnap = await db
      .collection('users').doc(uid)
      .collection('alerts').get();

    for (const alertDoc of alertsSnap.docs) {
      const animeId = alertDoc.id;
      if (!alertedAnime.has(animeId)) alertedAnime.set(animeId, new Set());
      alertedAnime.get(animeId).add(uid);
    }
  }));

  if (alertedAnime.size === 0) {
    console.log('No alerted anime, skipping precise reminder');
    return;
  }

  // Query AniList for episodes airing in the next 15 min
  const ids       = Array.from(alertedAnime.keys()).map(id => parseInt(id)).filter(Boolean);
  const nowSec    = Math.floor(Date.now() / 1000);
  const windowEnd = nowSec + (15 * 60);

  // AniList caps at ~50 ids per query, chunk if necessary
  const chunkSize = 50;
  const allSchedules = [];
  for (let i = 0; i < ids.length; i += chunkSize) {
    const chunk = ids.slice(i, i + chunkSize);
    const data  = await anilistQuery(`
      query($ids: [Int], $from: Int, $to: Int) {
        Page(page: 1, perPage: 50) {
          airingSchedules(mediaId_in: $ids, airingAt_greater: $from, airingAt_lesser: $to) {
            episode
            airingAt
            media {
              id
              title { romaji english }
            }
          }
        }
      }
    `, { ids: chunk, from: nowSec, to: windowEnd });
    const schedules = data?.data?.Page?.airingSchedules ?? [];
    allSchedules.push(...schedules);
  }

  if (allSchedules.length === 0) {
    console.log('No episodes airing in next 15 min for alerted anime');
    return;
  }

  // For each airing episode, send to all users who alerted on it (dedup via firedAlerts)
  for (const s of allSchedules) {
    const animeIdStr = String(s.media.id);
    const uids       = alertedAnime.get(animeIdStr);
    if (!uids) continue;

    const title      = s.media.title.english || s.media.title.romaji;
    const fireKey    = `${animeIdStr}_${s.episode}`;
    const minsUntil  = Math.max(0, Math.round((s.airingAt - nowSec) / 60));

    await Promise.allSettled(Array.from(uids).map(async uid => {
      // Dedup: skip if already fired for this anime+episode within last 24h
      const firedRef = db
        .collection('users').doc(uid)
        .collection('firedAlerts').doc(fireKey);
      const firedDoc = await firedRef.get();
      if (firedDoc.exists) {
        const firedAt = firedDoc.data()?.firedAt?.toMillis?.() ?? 0;
        if (Date.now() - firedAt < 24 * 60 * 60 * 1000) return;
      }

      await sendToUser(uid, {
        notification: {
          title,
          body: minsUntil > 1
            ? `Episode ${s.episode} airs in ${minsUntil} minutes`
            : `Episode ${s.episode} airs in 1 minute`,
        },
        data: {
          type:    'episode_reminder',
          animeId: animeIdStr,
          episode: String(s.episode),
        },
        android: { notification: { channelId: 'aruku_reminder', color: '#E8624A' } },
        apns:    { payload: { aps: { badge: 1 } } },
      });

      await firedRef.set({
        firedAt: new Date(),
        animeId: animeIdStr,
        episode: s.episode,
      });
    }));
  }

  console.log(`Precise reminder run complete: ${allSchedules.length} episodes airing soon`);
});

// ─────────────────────────────────────────────────────────────────────────────
// 3. Weekly Recap Digest — every Sunday at 11:00 UTC
// ─────────────────────────────────────────────────────────────────────────────

exports.weeklyRecap = onSchedule('0 11 * * 0', async () => {
  const users = await getUsersWithPref('weekly_recap');
  const weekAgo = new Date(Date.now() - 7 * 86400 * 1000);

  await Promise.allSettled(users.map(async doc => {
    const uid = doc.id;

    const snap = await db
      .collection('users').doc(uid)
      .collection('animeList')
      .where('lastWatched', '>=', weekAgo)
      .get();

    if (snap.empty) return;

    const completed = snap.docs.filter(d => d.data().status === 'COMPLETED').length;
    const total     = snap.docs.length;
    const body      = completed > 0
      ? `You completed ${completed} anime this week. Your Wrapped is growing!`
      : `You tracked ${total} anime this week. Keep going!`;

    await sendToUser(uid, {
      notification: { title: 'Your week in anime 📺', body },
      data: { type: 'weekly_recap' },
      android: { notification: { channelId: 'aruku_general', color: '#E8624A' } },
      apns: { payload: { aps: { badge: 1 } } },
    });
  }));

  console.log(`Weekly recap sent to ${users.length} users`);
});

// ─────────────────────────────────────────────────────────────────────────────
// 4. Friend Activity — triggered when an activity doc is created
// ─────────────────────────────────────────────────────────────────────────────

exports.friendActivity = onDocumentCreated(
  'users/{uid}/activity/{activityId}',
  async event => {
    const actorUid = event.params.uid;
    const activity = event.data.data();

    const actorDoc  = await db.collection('users').doc(actorUid).get();
    const actorName = actorDoc.data()?.displayName ?? 'A friend';

    // Find all users who follow this actor
    const followersSnap = await db
      .collection('users')
      .where('following', 'array-contains', actorUid)
      .get();

    const verb = activity.status === 'COMPLETED'
      ? 'completed'
      : activity.status === 'WATCHING'
      ? 'started watching'
      : 'added';

    await Promise.allSettled(
      followersSnap.docs.map(async followerDoc => {
        // Check follower's social pref
        const followerPrefs = followerDoc.data().notifPrefs ?? {};
        if (followerPrefs.social === false) return;

        await sendToUser(followerDoc.id, {
          notification: {
            title: actorName,
            body:  `${actorName} ${verb} ${activity.animeTitle}`,
          },
          data: {
            type:       'social',
            animeId:    String(activity.animeId ?? ''),
            actorUid,
          },
          android: { notification: { channelId: 'aruku_social', color: '#E8624A' } },
          apns: { payload: { aps: { badge: 1 } } },
        });
      })
    );
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 5. Streak Alerts — daily at 20:00 UTC
//    Warns users who haven't watched anything today and have an active streak
// ─────────────────────────────────────────────────────────────────────────────

exports.streakAlerts = onSchedule('0 20 * * *', async () => {
  const users   = await getUsersWithPref('streak');
  const todayMs = new Date().setHours(0, 0, 0, 0);
  const today   = new Date(todayMs);

  await Promise.allSettled(users.map(async doc => {
    const uid = doc.id;

    // Check if user has any activity today
    const todayActivity = await db
      .collection('users').doc(uid)
      .collection('activity')
      .where('createdAt', '>=', today)
      .limit(1)
      .get();

    if (!todayActivity.empty) return; // already active today

    // Check if they have a recent streak (active yesterday)
    const yesterday = new Date(todayMs - 86400 * 1000);
    const yesterdayActivity = await db
      .collection('users').doc(uid)
      .collection('activity')
      .where('createdAt', '>=', yesterday)
      .where('createdAt', '<', today)
      .limit(1)
      .get();

    if (yesterdayActivity.empty) return; // no streak to protect

    await sendToUser(uid, {
      notification: {
        title: '🔥 Don\'t break your streak!',
        body:  'You haven\'t watched anything today. Keep the streak alive!',
      },
      data: { type: 'streak' },
      android: { notification: { channelId: 'aruku_streak', color: '#E8624A' } },
      apns: { payload: { aps: { badge: 1 } } },
    });
  }));

  console.log('Streak alert run complete');
});

// ─────────────────────────────────────────────────────────────────────────────
// HANJ CARDS — Card Catalogue + Unlock System
// ─────────────────────────────────────────────────────────────────────────────

/**
 * CARD CATALOGUE
 * Each card:
 *   id          — unique string key, stored in Firestore
 *   name        — display name
 *   description — flavour text shown on the card
 *   rarity      — 'common' | 'rare' | 'epic' | 'legendary' | 'seasonal' | 'secret'
 *   category    — 'watcher' | 'genre' | 'streak' | 'taste' | 'secret' | 'seasonal'
 *   points      — rarity-weighted score for leaderboard (future)
 *   secret      — if true, shows as ??? until unlocked
 *   check(stats)— pure function, returns true if user qualifies
 *                 stats shape defined in buildUserStats() below
 */
const CARD_CATALOGUE = [

  // ── Common ──────────────────────────────────────────────────
  {
    id: 'first_pull',
    name: 'First Pull',
    description: 'Every collection starts somewhere.',
    rarity: 'common', category: 'watcher', points: 10,
    check: s => s.completedCount >= 1,
  },
  {
    id: 'the_list_begins',
    name: 'The List Begins',
    description: 'Ten worlds queued and waiting.',
    rarity: 'common', category: 'watcher', points: 10,
    check: s => s.totalInList >= 10,
  },
  {
    id: 'rated',
    name: 'Rated',
    description: 'You have opinions. Share them.',
    rarity: 'common', category: 'taste', points: 10,
    check: s => s.ratedCount >= 1,
  },
  {
    id: 'genre_curious',
    name: 'Genre Curious',
    description: 'Three genres, three different worlds.',
    rarity: 'common', category: 'genre', points: 10,
    check: s => s.uniqueGenres >= 3,
  },

  // ── Rare ────────────────────────────────────────────────────
  {
    id: 'decade_hopper',
    name: 'Decade Hopper',
    description: 'From classic to current — you respect the lineage.',
    rarity: 'rare', category: 'watcher', points: 30,
    check: s => s.uniqueDecades >= 3,
  },
  {
    id: 'the_critic',
    name: 'The Critic',
    description: 'Ten ratings. Your taste is documented.',
    rarity: 'rare', category: 'taste', points: 30,
    check: s => s.ratedCount >= 10,
  },
  {
    id: 'binge_mode',
    name: 'Binge Mode',
    description: 'Five worlds, one month. No regrets.',
    rarity: 'rare', category: 'watcher', points: 30,
    check: s => s.maxCompletedInMonth >= 5,
  },
  {
    id: 'loyal',
    name: 'Loyal',
    description: 'Three months running. The habit has you.',
    rarity: 'rare', category: 'streak', points: 30,
    check: s => s.currentStreak >= 3,
  },
  {
    id: 'action_purist',
    name: 'Action Purist',
    description: 'The fight scenes chose you.',
    rarity: 'rare', category: 'genre', points: 30,
    check: s => (s.genreCounts['Action'] ?? 0) >= 10,
  },
  {
    id: 'sol_soul',
    name: 'Slice of Life Soul',
    description: 'You find the extraordinary in the ordinary.',
    rarity: 'rare', category: 'genre', points: 30,
    check: s => (s.genreCounts['Slice of Life'] ?? 0) >= 10,
  },
  {
    id: 'romance_run',
    name: 'Hopeless Romantic',
    description: 'Love stories hit different.',
    rarity: 'rare', category: 'genre', points: 30,
    check: s => (s.genreCounts['Romance'] ?? 0) >= 10,
  },
  {
    id: 'fantasy_pilgrim',
    name: 'Fantasy Pilgrim',
    description: 'You live in worlds that don\'t exist.',
    rarity: 'rare', category: 'genre', points: 30,
    check: s => (s.genreCounts['Fantasy'] ?? 0) >= 10,
  },

  // ── Epic ────────────────────────────────────────────────────
  {
    id: 'the_50_club',
    name: 'The 50 Club',
    description: 'Fifty worlds completed. You are not a casual.',
    rarity: 'epic', category: 'watcher', points: 100,
    check: s => s.completedCount >= 50,
  },
  {
    id: 'genre_lord',
    name: 'Genre Lord',
    description: 'Twenty deep in one genre. You own it.',
    rarity: 'epic', category: 'genre', points: 100,
    check: s => Object.values(s.genreCounts).some(c => c >= 20),
  },
  {
    id: 'harsh_critic',
    name: 'Harsh Critic',
    description: 'Your bar is high. Most things don\'t clear it.',
    rarity: 'epic', category: 'taste', points: 100,
    check: s => s.ratedCount >= 20 && s.averageRating > 0 && s.averageRating < 6,
  },
  {
    id: 'the_optimist',
    name: 'The Optimist',
    description: 'You see the best in everything you watch.',
    rarity: 'epic', category: 'taste', points: 100,
    check: s => s.ratedCount >= 20 && s.averageRating >= 8.5,
  },
  {
    id: 'decade_scholar',
    name: 'Decade Scholar',
    description: 'Five decades. You understand where anime came from.',
    rarity: 'epic', category: 'watcher', points: 100,
    check: s => s.uniqueDecades >= 5,
  },
  {
    id: 'obsessed',
    name: 'Obsessed',
    description: 'Ten anime in a single month. You had a month.',
    rarity: 'epic', category: 'watcher', points: 100,
    check: s => s.maxCompletedInMonth >= 10,
  },

  // ── Legendary ───────────────────────────────────────────────
  {
    id: 'the_100_club',
    name: 'The 100 Club',
    description: 'One hundred worlds. Few reach here.',
    rarity: 'legendary', category: 'watcher', points: 300,
    check: s => s.completedCount >= 100,
  },
  {
    id: 'year_of_anime',
    name: 'Year of Anime',
    description: 'Twelve consecutive months. Anime is not a hobby — it\'s a lifestyle.',
    rarity: 'legendary', category: 'streak', points: 300,
    check: s => s.currentStreak >= 12,
  },
  {
    id: 'all_seasons',
    name: 'All Seasons',
    description: 'Spring, Summer, Fall, Winter — you watched through all of it.',
    rarity: 'legendary', category: 'watcher', points: 300,
    check: s => s.seasonsCoveredThisYear >= 4,
  },
  {
    id: 'the_200_club',
    name: 'The 200 Club',
    description: 'Two hundred worlds. You are the library.',
    rarity: 'legendary', category: 'watcher', points: 500,
    check: s => s.completedCount >= 200,
  },

  // ── Secret (shown as ??? until unlocked) ───────────────────
  {
    id: 'cant_let_go',
    name: 'Can\'t Let Go',
    description: 'Dropped it. Came back. Some stories won\'t release you.',
    rarity: 'epic', category: 'secret', points: 100, secret: true,
    check: s => s.dropAndReadd >= 1,
  },
  {
    id: 'resurrection',
    name: 'Resurrection',
    description: 'Dropped and completed the same anime. The ending was worth it.',
    rarity: 'epic', category: 'secret', points: 100, secret: true,
    check: s => s.dropAndComplete >= 1,
  },
  {
    id: 'the_long_game',
    name: 'The Long Game',
    description: 'Plan to Watch for over a year. Patience rewarded.',
    rarity: 'rare', category: 'secret', points: 50, secret: true,
    check: s => s.longGameUnlocked,
  },
  {
    id: 'time_traveller',
    name: 'Time Traveller',
    description: 'Anime from five different decades. You\'ve seen where it all began.',
    rarity: 'epic', category: 'secret', points: 100, secret: true,
    check: s => s.uniqueDecades >= 5,
  },
  {
    id: 'the_purist',
    name: 'The Purist',
    description: 'Original and remake. You honour the source.',
    rarity: 'legendary', category: 'secret', points: 200, secret: true,
    check: s => s.originalAndRemake >= 1,
  },
  {
    id: 'dropout',
    name: 'Dropout',
    description: 'Ten dropped. No shame — taste is selective.',
    rarity: 'rare', category: 'secret', points: 30, secret: true,
    check: s => s.droppedCount >= 10,
  },
  {
    id: 'ghost_of_seasons_past',
    name: 'Ghost of Seasons Past',
    description: 'Completed an anime on the anniversary of its air date.',
    rarity: 'legendary', category: 'secret', points: 200, secret: true,
    check: s => s.anniversaryComplete,
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// Seasonal cards — defined separately, date-gated
// ─────────────────────────────────────────────────────────────────────────────
const SEASONAL_CARDS = [
  {
    id: 'spring_2026_watcher',
    name: 'Spring 2026 Watcher',
    description: 'You were here for Spring 2026. This card doesn\'t come back.',
    rarity: 'seasonal', category: 'seasonal', points: 75,
    season: 'SPRING', year: 2026,
    startDate: '2026-04-01', endDate: '2026-06-30',
    check: s => s.completedInSeason['SPRING_2026'] >= 3,
  },
  {
    id: 'winter_arc_2026',
    name: 'Winter Arc',
    description: 'December and January — the coldest, longest watch sessions.',
    rarity: 'seasonal', category: 'seasonal', points: 75,
    startDate: '2025-12-01', endDate: '2026-01-31',
    check: s => s.completedInSeason['WINTER_ARC_2026'] >= 5,
  },
  {
    id: 'golden_week_2026',
    name: 'Golden Week Marathon',
    description: 'Golden Week 2026. You did not leave the house.',
    rarity: 'seasonal', category: 'seasonal', points: 75,
    startDate: '2026-04-29', endDate: '2026-05-05',
    check: s => s.completedInSeason['GOLDEN_WEEK_2026'] >= 2,
  },
  {
    id: 'summer_2026_watcher',
    name: 'Summer 2026 Watcher',
    description: 'Hot outside. You stayed in and watched.',
    rarity: 'seasonal', category: 'seasonal', points: 75,
    season: 'SUMMER', year: 2026,
    startDate: '2026-07-01', endDate: '2026-09-30',
    check: s => s.completedInSeason['SUMMER_2026'] >= 3,
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// Build user stats from Firestore — the single source of truth for all checks
// ─────────────────────────────────────────────────────────────────────────────
async function buildUserStats(uid) {
  const listSnap = await db
    .collection('users').doc(uid)
    .collection('animeList')
    .get();

  const docs = listSnap.docs.map(d => ({ id: d.id, ...d.data() }));

  let completedCount = 0;
  let droppedCount   = 0;
  let totalInList    = docs.length;
  let ratedCount     = 0;
  let totalRating    = 0;
  const genreCounts  = {};
  const decades      = new Set();
  const monthlyCompleted = {}; // 'YYYY-MM' -> count
  const seasonalCompleted = {}; // 'SEASON_YEAR' -> count
  const animeSeasons = new Set(); // which seasons of current year covered

  // Track drop-then-readd and drop-then-complete via activity
  let dropAndReadd   = 0;
  let dropAndComplete = 0;
  let longGameUnlocked = false;
  let anniversaryComplete = false;
  let originalAndRemake = 0;

  // Franchise tracking for The Purist (shared franchise name → statuses seen)
  const franchiseStatuses = {};

  const now = new Date();
  const currentYear = now.getFullYear();

  for (const doc of docs) {
    const status    = doc.status;
    const addedAt   = doc.addedAt?.toDate?.() ?? null;
    const genres    = doc.genres ?? [];
    const year      = doc.year ?? doc.seasonYear ?? null;
    const airDate   = doc.startDate ?? null; // 'YYYY-MM-DD' if stored
    const season    = doc.season ?? null;
    const title     = (doc.title ?? '').toLowerCase();

    if (status === 'COMPLETED') {
      completedCount++;

      // Monthly tracking
      if (addedAt) {
        const key = `${addedAt.getFullYear()}-${String(addedAt.getMonth() + 1).padStart(2, '0')}`;
        monthlyCompleted[key] = (monthlyCompleted[key] ?? 0) + 1;

        // Season coverage this year
        if (addedAt.getFullYear() === currentYear) {
          const m = addedAt.getMonth() + 1;
          if (m >= 1 && m <= 3)  animeSeasons.add('WINTER');
          if (m >= 4 && m <= 6)  animeSeasons.add('SPRING');
          if (m >= 7 && m <= 9)  animeSeasons.add('SUMMER');
          if (m >= 10 && m <= 12) animeSeasons.add('FALL');
        }

        // Seasonal card tracking
        const d = addedAt;
        if (d >= new Date('2026-04-01') && d <= new Date('2026-06-30'))
          seasonalCompleted['SPRING_2026'] = (seasonalCompleted['SPRING_2026'] ?? 0) + 1;
        if ((d >= new Date('2025-12-01') && d <= new Date('2025-12-31')) ||
            (d >= new Date('2026-01-01') && d <= new Date('2026-01-31')))
          seasonalCompleted['WINTER_ARC_2026'] = (seasonalCompleted['WINTER_ARC_2026'] ?? 0) + 1;
        if (d >= new Date('2026-04-29') && d <= new Date('2026-05-05'))
          seasonalCompleted['GOLDEN_WEEK_2026'] = (seasonalCompleted['GOLDEN_WEEK_2026'] ?? 0) + 1;
        if (d >= new Date('2026-07-01') && d <= new Date('2026-09-30'))
          seasonalCompleted['SUMMER_2026'] = (seasonalCompleted['SUMMER_2026'] ?? 0) + 1;

        // Anniversary check — completed on same month/day as air date
        if (airDate) {
          try {
            const air = new Date(airDate);
            if (air.getMonth() === d.getMonth() && air.getDate() === d.getDate()
                && air.getFullYear() !== d.getFullYear()) {
              anniversaryComplete = true;
            }
          } catch (_) {}
        }
      }
    }

    if (status === 'DROPPED') droppedCount++;

    // Ratings
    if (doc.userRating != null) {
      ratedCount++;
      totalRating += doc.userRating;
    }

    // Genres
    for (const g of genres) {
      genreCounts[g] = (genreCounts[g] ?? 0) + 1;
    }

    // Decades
    if (year) {
      decades.add(Math.floor(year / 10) * 10);
    }

    // Franchise tracking (The Purist)
    // Simple heuristic: strip trailing season indicators
    const baseName = title
      .replace(/\s*(season\s*\d+|s\d+|\d+nd|\d+rd|\d+th|\(.*\))\s*$/i, '')
      .trim();
    if (baseName) {
      if (!franchiseStatuses[baseName]) franchiseStatuses[baseName] = new Set();
      franchiseStatuses[baseName].add(status);
      // Long Game: addedAt vs completedAt — if plan_to_watch for 1+ year
      if (status === 'PLAN_TO_WATCH' && addedAt) {
        const ageMs = now - addedAt;
        if (ageMs > 365 * 24 * 60 * 60 * 1000) longGameUnlocked = true;
      }
    }
  }

  // Check franchise for original+remake (The Purist)
  for (const [, statuses] of Object.entries(franchiseStatuses)) {
    if (statuses.has('COMPLETED') && statuses.size >= 2) {
      originalAndRemake++;
    }
  }

  // Drop-then-readd / drop-then-complete — scan activity log
  try {
    const activitySnap = await db
      .collection('users').doc(uid)
      .collection('activity')
      .orderBy('createdAt', 'asc')
      .get();

    const byAnime = {};
    for (const doc of activitySnap.docs) {
      const d = doc.data();
      const aid = String(d.animeId ?? '');
      if (!aid) continue;
      if (!byAnime[aid]) byAnime[aid] = [];
      byAnime[aid].push(d.type ?? d.status);
    }

    for (const [, events] of Object.entries(byAnime)) {
      let dropped = false;
      for (const ev of events) {
        if (ev === 'DROPPED') { dropped = true; continue; }
        if (dropped) {
          if (ev === 'WATCHING' || ev === 'PLAN_TO_WATCH') dropAndReadd++;
          if (ev === 'COMPLETED') dropAndComplete++;
          dropped = false;
        }
      }
    }
  } catch (_) {}

  // Compute streak (consecutive months with completions)
  const sortedMonths = Object.keys(monthlyCompleted).sort();
  let currentStreak = 0;
  let maxStreak = 0;
  let prevMonth = null;
  for (const key of sortedMonths) {
    if (prevMonth) {
      const [py, pm] = prevMonth.split('-').map(Number);
      const [cy, cm] = key.split('-').map(Number);
      const expected = pm === 12 ? `${py + 1}-01` : `${py}-${String(pm + 1).padStart(2, '0')}`;
      if (key === expected) {
        currentStreak++;
      } else {
        currentStreak = 1;
      }
    } else {
      currentStreak = 1;
    }
    if (currentStreak > maxStreak) maxStreak = currentStreak;
    prevMonth = key;
  }

  // Max completed in any single month
  const maxCompletedInMonth = Math.max(0, ...Object.values(monthlyCompleted));

  return {
    completedCount,
    droppedCount,
    totalInList,
    ratedCount,
    averageRating: ratedCount > 0 ? totalRating / ratedCount : 0,
    genreCounts,
    uniqueGenres: Object.keys(genreCounts).length,
    uniqueDecades: decades.size,
    currentStreak: maxStreak,
    maxCompletedInMonth,
    seasonsCoveredThisYear: animeSeasons.size,
    completedInSeason: seasonalCompleted,
    dropAndReadd,
    dropAndComplete,
    longGameUnlocked,
    anniversaryComplete,
    originalAndRemake,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Check and unlock cards for a user
// Returns array of newly unlocked card ids
// ─────────────────────────────────────────────────────────────────────────────
async function checkAndUnlockCards(uid) {
  const stats = await buildUserStats(uid);

  // Get already-unlocked card ids
  const unlockedSnap = await db
    .collection('users').doc(uid)
    .collection('cards')
    .get();
  const alreadyUnlocked = new Set(unlockedSnap.docs.map(d => d.id));

  // Check all cards + active seasonal cards
  const now = new Date();
  const activeSeasonals = SEASONAL_CARDS.filter(c => {
    const start = new Date(c.startDate);
    const end   = new Date(c.endDate);
    return now >= start && now <= end;
  });

  const allCards = [...CARD_CATALOGUE, ...activeSeasonals];
  const newlyUnlocked = [];

  for (const card of allCards) {
    if (alreadyUnlocked.has(card.id)) continue;
    try {
      if (card.check(stats)) {
        // Write to Firestore
        await db
          .collection('users').doc(uid)
          .collection('cards')
          .doc(card.id)
          .set({
            id:          card.id,
            name:        card.name,
            description: card.description,
            rarity:      card.rarity,
            category:    card.category,
            points:      card.points,
            secret:      card.secret ?? false,
            unlockedAt:  new Date(),
          });
        newlyUnlocked.push(card);
      }
    } catch (err) {
      console.error(`Card check error for ${card.id}:`, err.message);
    }
  }

  // Update user's total card points
  if (newlyUnlocked.length > 0) {
    const pointsGained = newlyUnlocked.reduce((sum, c) => sum + c.points, 0);
    const userRef = db.collection('users').doc(uid);
    await userRef.set(
      { cardPoints: require('firebase-admin/firestore').FieldValue.increment(pointsGained) },
      { merge: true }
    );
  }

  return newlyUnlocked;
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Card Unlock Trigger — fires on every animeList write
// ─────────────────────────────────────────────────────────────────────────────

const { onDocumentWritten } = require('firebase-functions/v2/firestore');

exports.checkCardUnlocks = onDocumentWritten(
  'users/{uid}/animeList/{animeId}',
  async event => {
    const uid = event.params.uid;

    try {
      const newlyUnlocked = await checkAndUnlockCards(uid);

      if (newlyUnlocked.length === 0) return;

      // Send a notification for each new card
      for (const card of newlyUnlocked) {
        const rarityEmoji = {
          common:    '🃏',
          rare:      '💙',
          epic:      '💜',
          legendary: '🌟',
          seasonal:  '🌸',
          secret:    '🔮',
        }[card.rarity] ?? '🃏';

        await sendToUser(uid, {
          notification: {
            title: `${rarityEmoji} New card unlocked`,
            body:  `${card.name} — ${card.description}`,
          },
          data: {
            type:   'card_unlock',
            cardId: card.id,
            rarity: card.rarity,
          },
          android: {
            notification: { channelId: 'aruku_general', color: '#E8624A' },
          },
          apns: { payload: { aps: { badge: 1 } } },
        });
      }

      console.log(`Unlocked ${newlyUnlocked.length} cards for ${uid}:`,
        newlyUnlocked.map(c => c.id).join(', '));
    } catch (err) {
      console.error(`checkCardUnlocks error for ${uid}:`, err.message);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 7. Seasonal Card Expiry Check — runs daily at midnight UTC
//    Removes access to seasonal cards that are no longer in their window
//    (Cards already unlocked stay — the window only affects new unlocks)
// ─────────────────────────────────────────────────────────────────────────────

exports.seasonalCardCheck = onSchedule('0 0 * * *', async () => {
  // This just logs which seasonal cards are currently active.
  // The actual gating is in checkAndUnlockCards() via activeSeasonals filter.
  const now = new Date();
  const active = SEASONAL_CARDS.filter(c =>
    now >= new Date(c.startDate) && now <= new Date(c.endDate)
  );
  console.log(`Active seasonal cards: ${active.map(c => c.id).join(', ') || 'none'}`);
});

// ═════════════════════════════════════════════════════════════════════════════
// 7. Tomo — AI anime companion (callable)
//    Reads the user's animeList for context, talks anime, searches the web for
//    current news / airing / theories, and stays spoiler-aware.
//
//    Setup:
//      cd functions && npm install @anthropic-ai/sdk
//      firebase deploy --only functions:chatWithTomo   (key already set as secret)
// ═════════════════════════════════════════════════════════════════════════════

const TOMO_MODEL          = 'claude-sonnet-4-6'; // balanced: smart + affordable
const TOMO_DAILY_CAP      = 40;                  // messages per user per day
const TOMO_MAX_HISTORY    = 20;                  // prior turns sent to Claude

const TOMO_PERSONA = `
You are Loki, the AI anime companion living inside Hanj, an anime tracking app.

You're clever, quick-witted, and a little mischievous — the friend who's seen every
anime and loves talking about it, with a playful streak. You have sharp opinions and
you're not shy about them.

VOICE:
- Warm but with an edge of wit. Playful, a touch teasing, never mean.
- Talk like a clever friend texting, not a textbook. Short, punchy, alive.
- Light anime vernacular is fine (arc, cour, best girl, peak fiction) but don't
  overdo it or sound like a try-hard.
- You can be funny and a little dramatic about a great episode.

THE GOLDEN RULE — SPOILERS (this is core to who you are — lean into it):
- You know everything that happens in every show. That's exactly what makes you so
  good at NOT spoiling — you're a trickster who guards secrets, never one who leaks them.
- For a show the user is WATCHING, you do NOT know their exact episode — so assume they
  could be anywhere and NEVER reveal, hint at, or confirm any major plot point, death,
  twist, or ending. If they want specifics, ASK what episode they're on first, then keep
  everything at or before that point.
- For COMPLETED shows, discuss freely.
- For PLAN TO WATCH or any show not on their list, assume zero knowledge and stay
  spoiler-free unless they explicitly say they've finished it.
- Have fun with it: "Oh, I know EXACTLY what's coming. Will I tell you? Not a chance 😏"
  — but never actually let anything slip.
- If they ask what's ahead, answer spoiler-free or ask if they truly want spoilers, and
  only proceed if they clearly say yes.
- This rule overrides everything. Spoiling a friend is the one line you never cross.

USING THE WEB:
- For current/airing/upcoming anime, recent news, release dates, or fresh theories,
  use web search to get it right. Don't guess at dates or news. Weave facts in
  naturally and keep it conversational.

THEORIES:
- You LIVE for a good theory. Build them from what the user has actually seen plus public
  speculation — never let real knowledge of an ending leak into a theory for someone who
  isn't caught up. (You can hint that you know more than you're saying — that's your charm.)

FORMAT:
- Keep replies tight and chatty. No headers or bullet dumps unless they ask for a list.
  This is a conversation, not a report.
`;

function buildTomoListContext(docs) {
  if (!docs.length) {
    return 'The user has no anime on their list yet. Encourage them to add some and '
         + 'recommend based on what they tell you they like.';
  }

  const watching = [];
  const completed = [];
  const planning = [];
  const dropped = [];

  for (const d of docs) {
    const title = (d.title || d.animeTitle || 'Unknown').toString();
    const status = (d.status || '').toString().toUpperCase();
    if (status === 'COMPLETED')      completed.push(title);
    else if (status === 'PLANNING')  planning.push(title);
    else if (status === 'DROPPED')   dropped.push(`${title} (dropped)`);
    else                             watching.push(title); // WATCHING / PAUSED / default
  }

  const parts = ["THE USER'S LIST (use for spoiler safety):"];
  if (watching.length)  parts.push(`\nCURRENTLY WATCHING (you don't know their episode — ask before discussing specifics, no spoilers):\n- ${watching.join('\n- ')}`);
  if (completed.length) parts.push(`\nCOMPLETED (safe to discuss fully):\n- ${completed.join('\n- ')}`);
  if (planning.length)  parts.push(`\nPLAN TO WATCH (assume zero knowledge, no spoilers):\n- ${planning.join('\n- ')}`);
  if (dropped.length)   parts.push(`\nDROPPED:\n- ${dropped.join('\n- ')}`);
  return parts.join('\n');
}

exports.chatWithTomo = onCall(
  { secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 120 },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in to chat with Loki.');

    const userMessage = (request.data?.message || '').toString().trim();
    if (!userMessage) throw new HttpsError('invalid-argument', 'Message is empty.');

    const incomingHistory = Array.isArray(request.data?.history)
      ? request.data.history.slice(-TOMO_MAX_HISTORY)
      : [];

    // Daily cap
    const today = new Date().toISOString().slice(0, 10);
    const usageRef = db.collection('users').doc(uid)
                       .collection('companion_meta').doc('usage');
    const usageSnap = await usageRef.get();
    let count = 0;
    if (usageSnap.exists && usageSnap.data().date === today) {
      count = usageSnap.data().count || 0;
    }
    if (count >= TOMO_DAILY_CAP) {
      throw new HttpsError('resource-exhausted',
        "You've hit today's message limit with Loki. Back tomorrow!");
    }

    // Read the user's list (same collection the rest of the app uses).
    let docs = [];
    try {
      const snap = await db.collection('users').doc(uid)
                          .collection('animeList').get();
      docs = snap.docs.map(d => d.data());
    } catch (e) {
      console.warn('Tomo: could not read animeList for', uid, e);
    }
    const listContext = buildTomoListContext(docs);

    // Assemble messages.
    const messages = incomingHistory
      .filter(m => m && m.text && (m.role === 'user' || m.role === 'assistant'))
      .map(m => ({ role: m.role, content: m.text }));
    messages.push({ role: 'user', content: userMessage });

    // Call Claude with server-side web search.
    const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() });
    let reply = '';
    try {
      const resp = await anthropic.messages.create({
        model: TOMO_MODEL,
        max_tokens: 1024,
        system: `${TOMO_PERSONA}\n\n${listContext}`,
        messages,
        tools: [
          { type: 'web_search_20260209', name: 'web_search', max_uses: 4 },
        ],
      });
      reply = resp.content
        .filter(b => b.type === 'text')
        .map(b => b.text)
        .join('\n')
        .trim();
    } catch (e) {
      console.error('Tomo: Anthropic call failed:', e);
      throw new HttpsError('internal', 'Loki had a hiccup. Try again in a moment.');
    }
    if (!reply) reply = "Hmm, I blanked on that one — mind rephrasing?";

    // Persist + bump counter (best-effort).
    const chatCol = db.collection('users').doc(uid).collection('companion_chat');
    const now = Date.now();
    await Promise.all([
      chatCol.add({ role: 'user', text: userMessage, ts: now }),
      chatCol.add({ role: 'assistant', text: reply, ts: now + 1 }),
      usageRef.set({ date: today, count: count + 1 }, { merge: true }),
    ]).catch(e => console.warn('Tomo: persist failed (non-fatal):', e));

    return { reply, remaining: TOMO_DAILY_CAP - (count + 1) };
  }
);
