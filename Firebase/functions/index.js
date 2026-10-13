/**
 * Firebase Functions v2 – Full Notification System + Cleanup
 * (KEEP deleteAccount – ADD cleanup chat + todo)
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onDocumentDeleted } = require("firebase-functions/v2/firestore");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");

function buildIosApnsAlert(title, body) {
  return {
    headers: {
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    payload: {
      aps: {
        alert: {
          title,
          body,
        },
        sound: "default",
        badge: 1,
      },
    },
  };
}



admin.initializeApp();
const db = admin.firestore();
/**
 * Push to several users (group events). Reads each user doc once,
 * skips users currently viewing `skipIfViewingChat`, and drops tokens
 * FCM reports as invalid.
 */
async function pushToUsers(uids, { title, body, data, skipIfViewingChat }) {
  const unique = [...new Set(uids.filter(Boolean))];
  if (unique.length === 0) return;

  const snaps = await db.getAll(...unique.map((u) => db.collection("users").doc(u)));
  for (const snap of snaps) {
    if (!snap.exists) continue;
    const user = snap.data();
    if (skipIfViewingChat && user.activeChatEventId === skipIfViewingChat) continue;

    const tokens = Array.isArray(user.notificationTokens) ? user.notificationTokens : [];
    if (tokens.length === 0) continue;

    try {
      const res = await admin.messaging().sendEachForMulticast({
        tokens,
        data,
        apns: buildIosApnsAlert(title, body),
      });
      const invalid = [];
      res.responses.forEach((r, idx) => {
        const code = r.error?.code || "";
        if (!r.success && (code === "messaging/registration-token-not-registered" ||
                           code === "messaging/invalid-registration-token")) {
          invalid.push(tokens[idx]);
        }
      });
      if (invalid.length > 0) {
        await snap.ref.update({
          notificationTokens: admin.firestore.FieldValue.arrayRemove(...invalid),
        });
      }
    } catch (err) {
      logger.error("❌ pushToUsers failed", { uid: snap.id, error: err });
    }
  }
}

function extractHourWeekdayFromTimestamp(ts) {
  const d = new Date(ts.seconds * 1000);
  return {
    hour: d.getHours(),    // 0–23
    weekday: d.getDay(),  // 0–6 (Sun–Sat)
  };
}

/* ============================================================
   1) CLEANUP EXPIRED EVENTS + BUSY SLOTS + CHAT
   (FIXED – RUNNABLE VERSION)
   ============================================================ */
exports.cleanupExpiredEvents = onSchedule(
  {
    // Was every 5 minutes. The app already hides past events itself, so
    // hourly is enough and costs 12x fewer runs.
    schedule: "every 60 minutes",
    timeZone: "Asia/Ho_Chi_Minh",
  },
  async () => {
    const nowSec = Math.floor(Date.now() / 1000);
    const now = admin.firestore.Timestamp.now();
    logger.log("🧹 Cleanup expired EVENTS started");

    // Only read events that already ended (was: the WHOLE collection every run).
    // `end` = legacy field name, normally an empty query.
    const [byEndTime, byLegacyEnd] = await Promise.all([
      db.collection("events").where("endTime", "<=", now).get(),
      db.collection("events").where("end", "<=", now).get(),
    ]);
    const seen = new Set();
    const expiredDocs = [...byEndTime.docs, ...byLegacyEnd.docs]
      .filter((d) => (seen.has(d.id) ? false : seen.add(d.id)));

    for (const evDoc of expiredDocs) {
      const ev = evDoc.data();
      if (!ev) continue;

      // ✅ CHỈ HỖ TRỢ FIRESTORE TIMESTAMP
      const endTs = ev.endTime || ev.end;
      if (!endTs || typeof endTs.seconds !== "number") {
        // ❗ KHÔNG XOÁ nếu data không chuẩn
        continue;
      }

      if (endTs.seconds > nowSec) {
        // ✅ Event còn hạn → SKIP
        continue;
      }

      const eventId = evDoc.id;
      logger.log(`⏰ Expired event → delete ${eventId}`);

      // =====================================================
      // 🧠 USER STATS (AGGREGATE) — ADDED, SAFE
      // =====================================================
      if (ev.owner && ev.startTime && ev.startTime.seconds) {
        const { hour, weekday } =
          extractHourWeekdayFromTimestamp(ev.startTime);

        const statsRef = db.collection("userStats").doc(ev.owner);

        await statsRef.set(
          {
            busyByHour: {
              [hour]: admin.firestore.FieldValue.increment(1),
            },
            busyByWeekday: {
              [weekday]: admin.firestore.FieldValue.increment(1),
            },
            totalEvents: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }

      // 1️⃣ Delete event (GIỮ NGUYÊN)
      await evDoc.ref.delete();

      // 2️⃣ Remove busySlots LIÊN QUAN event (GIỮ NGUYÊN)
      if (Array.isArray(ev.participants)) {
        for (const uid of ev.participants) {
          const calRef = db.collection("publicCalendar").doc(uid);
          const calSnap = await calRef.get();
          if (!calSnap.exists) continue;

          const slots = calSnap.data().busySlots || [];
          const cleaned = slots.filter(
            (s) => String(s.id) !== String(eventId)
          );

          if (cleaned.length !== slots.length) {
            await calRef.update({ busySlots: cleaned });
          }
        }
      }

      // 3️⃣ Delete chat (GIỮ NGUYÊN)
      await admin.firestore().recursiveDelete(
        db.collection("chats").doc(eventId)
      );
    }

    logger.log("✅ Cleanup expired EVENTS finished");
    return null;
  }
);



/* ============================================================
   2) deleteAccount – XÓA USER + DỮ LIỆU (GIỮ NGUYÊN)
   ============================================================ */
exports.deleteAccount = onCall(async (request) => {
  if (!request.auth) {
    throw new Error("User must be authenticated.");
  }

  const uid = request.auth.uid;

  const userRef = db.collection("users").doc(uid);
  const publicRef = db.collection("publicCalendar").doc(uid);

  const eventsOwned = await db
    .collection("events")
    .where("owner", "==", uid)
    .get();

  const eventsCreated = await db
    .collection("events")
    .where("createdBy", "==", uid)
    .get();

  const accessRef = db.collection("calendarAccess").doc(uid);
  const allowed = await accessRef.collection("allowed").get();
  const requests = await accessRef.collection("requests").get();

  const allAccess = await db.collection("calendarAccess").get();

  // v2.5: custom booking link (/c/<handle>) points at this uid
  const userSnap = await userRef.get();
  const handle = userSnap.exists ? userSnap.get("handle") : null;
  let handleRef = null;
  if (typeof handle === "string" && handle) {
    const h = await db.collection("handles").doc(handle).get();
    if (h.exists && h.get("uid") === uid) handleRef = h.ref;
  }

  const batch = db.batch();

  // Core user data
  batch.delete(userRef);
  batch.delete(publicRef);
  batch.delete(accessRef);
  batch.delete(db.collection("userStats").doc(uid));
  if (handleRef) batch.delete(handleRef);

  // Events
  eventsOwned.forEach((d) => batch.delete(d.ref));
  eventsCreated.forEach((d) => batch.delete(d.ref));

  // Access control
  allowed.forEach((d) => batch.delete(d.ref));
  requests.forEach((d) => batch.delete(d.ref));

  for (const doc of allAccess.docs) {
    const req = doc.ref.collection("requests").doc(uid);
    const snap = await req.get();
    if (snap.exists) batch.delete(req);
  }

  await batch.commit();

  // Profile photo (Firebase Storage avatars/{uid}.jpg) — may not exist
  try {
    await admin.storage().bucket().file(`avatars/${uid}.jpg`).delete({ ignoreNotFound: true });
  } catch (err) {
    logger.error("deleteAccount: avatar delete failed", { uid, error: err });
  }

  // Delete Firebase Auth user
  await admin.auth().deleteUser(uid);

  return { success: true };
});
/* ============================================================
   3) PUSH – NEW EVENT CREATED FOR OTHER USER
   ============================================================ */
exports.pushNewEvent = onDocumentCreated(
  "events/{eventId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (!data) return;

    const { title, owner, sharedUser, createdBy, participants } = data;
    if (!createdBy) return;

    // Người nhận = mọi người trong lịch trừ người tạo (1-1 và nhóm)
    const receivers = [
      ...(Array.isArray(participants) ? participants : []),
      owner,
      sharedUser,
    ].filter((u) => u && u !== createdBy);
    if (receivers.length === 0) return;

    await pushToUsers(receivers, {
      title: "New event added",
      body: title
        ? `“${title}” has been added to your calendar`
        : "A new event has been added to your calendar",
      data: { type: "event", eventId: event.params.eventId },
    });

    logger.log(
      `🔔 Push new event → ${new Set(receivers).size} user(s) | eventId=${event.params.eventId}`
    );
  }
);



exports.pushNewChatMessage = onDocumentCreated(
  "chats/{eventId}/messages/{messageId}",
  async (event) => {
    const msgSnap = event.data;
    if (!msgSnap) return;

    const msg = msgSnap.data();
    if (!msg) return;

    const { senderId, senderName, text, latitude, longitude } = msg;
    if (!senderId) return;

    const eventId = event.params.eventId;

    // 1️⃣ Lấy chat meta
    const chatSnap = await db.collection("chats").doc(eventId).get();
    if (!chatSnap.exists) return;

    const participants = chatSnap.data().participants || [];
    // Everyone in the chat except the sender (1-1 and group events)
    const receivers = participants.filter((u) => u && u !== senderId);
    if (receivers.length === 0) return;

    // Nội dung push
    let bodyText = "You have a new message";
    if (text && text.trim()) {
      bodyText = text;
    } else if (latitude && longitude) {
      bodyText = "📍 Location shared";
    }
    const titleText = senderName || "New message";

    await pushToUsers(receivers, {
      title: titleText,
      body: bodyText,
      data: { type: "chat", eventId },
      skipIfViewingChat: eventId, // ❌ không push cho người đang mở chat này
    });

    logger.log(`💬 Push chat → ${receivers.length} user(s) | eventId=${eventId}`);
  }
);


/* ============================================================
   4) PUSH – CALENDAR ACCESS REQUEST (NEW)
   ============================================================ */
exports.pushCalendarAccessRequest = onDocumentCreated(
  "calendarAccess/{ownerUid}/requests/{requesterUid}",
  async (event) => {

    const { ownerUid, requesterUid } = event.params;
    const requestData = event.data?.data();
    if (!requestData) return;

    logger.log("📩 New calendar access request", {
      ownerUid,
      requesterUid,
    });

    // 1️⃣ Lấy user OWNER (người nhận request)
    const ownerSnap = await db.collection("users").doc(ownerUid).get();
    if (!ownerSnap.exists) return;

    const tokens = ownerSnap.data().notificationTokens || [];
    if (!Array.isArray(tokens) || tokens.length === 0) return;

    // 2️⃣ Nội dung push
    const requesterName =
      requestData.name && requestData.name.length > 0
        ? requestData.name
        : "Someone";

    const titleText = "New calendar access request";
    const bodyText = `${requesterName} wants to access your calendar`;

    // 3️⃣ Gửi push (ĐÚNG CHUẨN iOS)
    try {
      const res = await admin.messaging().sendEachForMulticast({
        tokens,
        data: {
          type: "calendar_access_request",
          requesterUid,
        },
        apns: buildIosApnsAlert(titleText, bodyText),
      });

      logger.log("✅ Calendar access request push sent", {
        ownerUid,
        successCount: res.successCount,
        failureCount: res.failureCount,
      });

      // 4️⃣ Cleanup token lỗi (GIỮ NGUYÊN)
      const invalidTokens = [];
      res.responses.forEach((r, idx) => {
        if (!r.success) {
          const code = r.error?.code || "";
          if (
            code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token"
          ) {
            invalidTokens.push(tokens[idx]);
          }
        }
      });

      if (invalidTokens.length > 0) {
        await db.collection("users").doc(ownerUid).update({
          notificationTokens: admin.firestore.FieldValue.arrayRemove(
            ...invalidTokens
          ),
        });
        logger.log("🧹 Removed invalid notification tokens", invalidTokens.length);
      }

    } catch (err) {
      logger.error("❌ Failed to send calendar access request push", err);
    }
  }
);


/* ============================================================
   5) CLEANUP EXPIRED BUSY HOURS ONLY (SAFE, SIMPLE)
   ============================================================ */
exports.cleanupExpiredBusyHoursOnly = onSchedule(
  {
    // Was hourly (reads every publicCalendar doc each time). Clients and the
    // web page already ignore past slots, so once a night is enough.
    schedule: "0 3 * * *",
    timeZone: "Asia/Ho_Chi_Minh",
  },
  async () => {
    const nowSec = Math.floor(Date.now() / 1000);
    logger.log("🧹 Cleanup expired busy hours ONLY started");

    const calendars = await db.collection("publicCalendar").get();
    let removed = 0;

    for (const doc of calendars.docs) {
      const slots = Array.isArray(doc.data().busySlots)
        ? doc.data().busySlots
        : [];

      const cleaned = slots.filter((slot) => {
        // ❗ Không chắc → GIỮ
        if (!slot || slot.end == null) return true;

        let endSec;

        // hỗ trợ Timestamp
        if (typeof slot.end === "object" && slot.end.seconds) {
          endSec = slot.end.seconds;
        } else {
          const n = Number(slot.end);
          if (Number.isNaN(n)) return true;
          endSec = n > 10_000_000_000 ? Math.floor(n / 1000) : n;
        }

        return endSec > nowSec;
      });

      if (cleaned.length !== slots.length) {
        removed += slots.length - cleaned.length;
        await doc.ref.update({ busySlots: cleaned });
      }
    }

    logger.log("✅ Cleanup expired busy hours ONLY finished", { removed });
    return null;
  }
);
/* ============================================================
   CLEAN CHAT WHEN EVENT IS DELETED MANUALLY BY USER
   ============================================================ */
exports.cleanupChatOnEventDelete = onDocumentDeleted(
  "events/{eventId}",
  async (event) => {
    const eventId = event.params.eventId;

    logger.log("🗑️ Event deleted manually → cleanup chat", eventId);

    const chatRef = db.collection("chats").doc(eventId);

    try {
      const snap = await chatRef.get();
      if (!snap.exists) {
        logger.log("ℹ️ No chat found for event", eventId);
        return;
      }

      // 🔥 XOÁ TOÀN BỘ CHAT + SUBCOLLECTIONS (messages, todos, ...)
      await admin.firestore().recursiveDelete(chatRef);

      logger.log("✅ Chat cleaned for deleted event", eventId);
    } catch (err) {
      logger.error("❌ Failed to cleanup chat", {
        eventId,
        error: err,
      });
    }
  }
);
/* ============================================================
   6) PUSH – EVENT REMOVED BY PARTICIPANT
   ============================================================ */
exports.pushEventRemoved = onDocumentDeleted(
  "events/{eventId}",
  async (event) => {
    const eventId = event.params.eventId;
    const data = event.data?.data();
    if (!data) return;

    const { title, participants, deletedBy } = data;

    if (!Array.isArray(participants) || participants.length < 2) return;

    if (!deletedBy) {
      logger.log("ℹ️ Event deleted without deletedBy – skip push", eventId);
      return;
    }

    // Người nhận = mọi người còn lại (1-1 và nhóm)
    const receivers = participants.filter((u) => u && u !== deletedBy);
    if (receivers.length === 0) return;

    // Lấy thông tin người xoá
    const deleterSnap = await db.collection("users").doc(deletedBy).get();
    const deleterName =
      deleterSnap.exists && deleterSnap.data().name
        ? deleterSnap.data().name
        : "Someone";

    await pushToUsers(receivers, {
      title: "Event removed",
      body: title
        ? `“${title}” was removed by ${deleterName}`
        : `An event was removed by ${deleterName}`,
      data: { type: "event_removed", eventId },
    });

    logger.log("🗑️ Push event removed sent", { eventId, receivers: receivers.length });
  }
);

/* ============================================================
   7) PUSH – ADDED TO A (GROUP) EVENT
   ============================================================ */
exports.pushParticipantsAdded = onDocumentUpdated(
  "events/{eventId}",
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;
    if (after.deletedBy) return; // the app writes delete metadata right before deleting

    const oldSet = new Set(Array.isArray(before.participants) ? before.participants : []);
    const added = (Array.isArray(after.participants) ? after.participants : [])
      .filter((u) => u && !oldSet.has(u) && u !== after.createdBy);
    if (added.length === 0) return; // most updates (time, title, votes) end here — no reads

    await pushToUsers(added, {
      title: "Added to an event",
      body: after.title
        ? `You were added to “${after.title}”`
        : "You were added to an event",
      data: { type: "event", eventId: event.params.eventId },
    });

    logger.log("👥 Push participants added", { eventId: event.params.eventId, added: added.length });
  }
);
