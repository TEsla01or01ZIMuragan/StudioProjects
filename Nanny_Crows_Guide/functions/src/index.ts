import { randomInt } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getMessaging, type MulticastMessage } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

initializeApp();

const db = getFirestore();
const messaging = getMessaging();
const inviteCodePattern = /^\d{6}$/;

export const generateStudentInviteCode = onDocumentCreated(
  "users/{userId}",
  async (event) => {
    const userId = event.params.userId;
    const profile = event.data?.data();
    if (!profile || !["student", "child"].includes(profile.role)) return;

    for (let attempt = 0; attempt < 20; attempt++) {
      const code = String(randomInt(100_000, 1_000_000));
      const created = await db.runTransaction(async (transaction) => {
        const codeRef = db.collection("inviteCodes").doc(code);
        const userRef = db.collection("users").doc(userId);
        const [codeSnapshot, userSnapshot] = await Promise.all([
          transaction.get(codeRef),
          transaction.get(userRef),
        ]);
        if (codeSnapshot.exists || !userSnapshot.exists) return false;
        transaction.create(codeRef, {
          studentId: userId,
          createdAt: FieldValue.serverTimestamp(),
        });
        transaction.update(userRef, { inviteCode: code });
        return true;
      });
      if (created) return;
    }
    throw new Error("Unable to allocate a unique student invite code.");
  },
);

export const linkParentToStudent = onCall(async (request) => {
  const parentId = request.auth?.uid;
  if (!parentId) throw new HttpsError("unauthenticated", "Sign in first.");
  const code = request.data?.inviteCode;
  if (typeof code !== "string" || !inviteCodePattern.test(code)) {
    throw new HttpsError("invalid-argument", "Enter a valid six-digit code.");
  }

  const attemptRef = db.collection("inviteAttempts").doc(parentId);
  const codeRef = db.collection("inviteCodes").doc(code);
  const parentRef = db.collection("users").doc(parentId);

  const result = await db.runTransaction(async (transaction) => {
    const [attemptSnapshot, codeSnapshot, parentSnapshot] =
      await Promise.all([
        transaction.get(attemptRef),
        transaction.get(codeRef),
        transaction.get(parentRef),
      ]);

    const now = Date.now();
    const attemptData = attemptSnapshot.data();
    const windowStart = attemptData?.windowStart?.toMillis?.() as number | undefined;
    const attempts =
      windowStart !== undefined && now - windowStart < 15 * 60 * 1000
        ? Number(attemptData?.count ?? 0)
        : 0;
    if (attempts >= 5) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many attempts. Try again in 15 minutes.",
      );
    }

    const studentId = codeSnapshot.data()?.studentId;
    const studentRef =
      typeof studentId === "string" ? db.collection("users").doc(studentId) : null;
    const studentSnapshot = studentRef
      ? await transaction.get(studentRef)
      : null;

    transaction.set(attemptRef, {
      count: attempts + 1,
      windowStart:
        attempts === 0 ? new Date(now) : attemptData?.windowStart,
    });

    if (!parentSnapshot.exists || parentSnapshot.data()?.role !== "parent") {
      return { error: "permission-denied" as const };
    }
    const student = studentSnapshot?.data();
    if (
      !studentSnapshot?.exists ||
      student === undefined ||
      !["student", "child"].includes(String(student.role)) ||
      studentId === parentId
    ) {
      return { error: "not-found" as const };
    }

    const parent = parentSnapshot.data()!;
    const currentChildren = (parent.childrenIds ?? []) as string[];
    const currentClasses = (parent.childClassIds ?? []) as string[];
    const classId = student.classId;
    transaction.update(parentRef, {
      childrenIds: FieldValue.arrayUnion(studentId),
      ...(typeof classId === "string" && classId.length > 0
        ? { childClassIds: FieldValue.arrayUnion(classId) }
        : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      error: null,
      alreadyLinked: currentChildren.includes(studentId),
      classAlreadyLinked:
        typeof classId !== "string" || currentClasses.includes(classId),
    };
  });

  if (result.error === "permission-denied") {
    throw new HttpsError(
      "permission-denied",
      "Only parent profiles can link students.",
    );
  }
  if (result.error === "not-found") {
    throw new HttpsError("not-found", "The invite code is invalid.");
  }
  return { linked: true, alreadyLinked: result.alreadyLinked };
});

export const notifyClassOfAssignment = onDocumentCreated(
  "assignments/{assignmentId}",
  async (event) => {
    const assignment = event.data?.data();
    if (!assignment) return;
    const students = await db
      .collection("users")
      .where("role", "in", ["student", "child"])
      .where("classId", "==", assignment.classId)
      .get();
    const tokens = students.docs
      .map((student) => student.get("fcmToken"))
      .filter(
        (token): token is string =>
          typeof token === "string" && token.length > 0,
      );
    await sendInChunks(tokens, {
      notification: {
        title: "Новое задание",
        body: String(assignment.title ?? "Проверьте список заданий"),
      },
      data: {
        type: "assignment",
        assignmentId: event.params.assignmentId,
      },
    });
  },
);

export const syncParentClassAccess = onDocumentUpdated(
  "users/{userId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (
      !before ||
      !after ||
      !["student", "child"].includes(after.role) ||
      before.classId === after.classId
    ) {
      return;
    }

    const parents = await db
      .collection("users")
      .where("childrenIds", "array-contains", event.params.userId)
      .get();
    for (let offset = 0; offset < parents.docs.length; offset += 400) {
      const batch = db.batch();
      const parentChunk = parents.docs.slice(offset, offset + 400);
      for (const parent of parentChunk) {
        const childIds = (parent.get("childrenIds") ?? []) as string[];
        const children = await Promise.all(
          childIds.map((childId) => db.collection("users").doc(childId).get()),
        );
        const classIds = [
          ...new Set(
            children
              .map((child) => child.get("classId"))
              .filter(
                (classId): classId is string =>
                  typeof classId === "string" && classId.length > 0,
              ),
          ),
        ];
        batch.update(parent.ref, { childClassIds: classIds });
      }
      await batch.commit();
    }
  },
);

export const notifyWhenSubmissionIsGraded = onDocumentUpdated(
  "submissions/{submissionId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (
      !before ||
      !after ||
      before.status === "graded" ||
      after.status !== "graded"
    ) {
      return;
    }

    const studentId = after.studentId;
    const subjectId = after.subjectId;
    const grade = Number(after.grade);
    if (
      typeof studentId !== "string" ||
      studentId.length === 0 ||
      typeof subjectId !== "string" ||
      subjectId.length === 0 ||
      !Number.isFinite(grade) ||
      grade < 1 ||
      grade > 100
    ) {
      throw new Error("Graded submission is missing a valid student, subject, or grade.");
    }
    const eventRef = db.collection("gradeSummaryEvents").doc(event.id);
    const summaryRef = db
      .collection("gradeSummaries")
      .doc(studentId)
      .collection("subjects")
      .doc(subjectId);
    await db.runTransaction(async (transaction) => {
      const [processed, summarySnapshot] = await Promise.all([
        transaction.get(eventRef),
        transaction.get(summaryRef),
      ]);
      if (processed.exists) return;
      const summary = summarySnapshot.data();
      const count = Number(summary?.count ?? 0) + 1;
      const sum = Number(summary?.sum ?? 0) + grade;
      transaction.set(summaryRef, {
        count,
        sum,
        average: sum / count,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(eventRef, {
        studentId,
        submissionId: event.params.submissionId,
        createdAt: FieldValue.serverTimestamp(),
      });
    });

    const [student, parents] = await Promise.all([
      db.collection("users").doc(studentId).get(),
      db
        .collection("users")
        .where("childrenIds", "array-contains", studentId)
        .get(),
    ]);
    const tokens = [
      student.get("fcmToken"),
      ...parents.docs.map((parent) => parent.get("fcmToken")),
    ].filter(
      (token): token is string => typeof token === "string" && token.length > 0,
    );
    await sendInChunks(tokens, {
      notification: {
        title: "Работа проверена",
        body: `Оценка: ${String(after.grade ?? "—")}`,
      },
      data: {
        type: "grade",
        submissionId: event.params.submissionId,
      },
    });
  },
);

async function sendInChunks(
  tokens: string[],
  payload: Omit<MulticastMessage, "tokens">,
) {
  const uniqueTokens = [...new Set(tokens)];
  for (let start = 0; start < uniqueTokens.length; start += 500) {
    const response = await messaging.sendEachForMulticast({
      ...payload,
      tokens: uniqueTokens.slice(start, start + 500),
    });
    if (response.failureCount > 0) {
      logger.warn("Some push notifications could not be delivered.", {
        failureCount: response.failureCount,
        errorCodes: response.responses
          .filter((result) => !result.success)
          .map((result) => result.error?.code),
      });
    }
  }
}
