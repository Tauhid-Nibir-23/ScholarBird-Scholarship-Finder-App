const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp();
const db = getFirestore();

const REQUIRED_FIELDS = {
  'Full Name': ['name', 'displayName'],
  Email: ['email'],
  Phone: ['phone'],
  Country: ['country'],
  Nationality: ['nationality'],
  'Date of Birth': ['dateOfBirth'],
  Gender: ['gender'],
  'Current Education': ['currentEducation', 'education', 'degree'],
  CGPA: ['cgpa'],
  'University/College': ['university'],
  'Graduation Year': ['graduationYear'],
};

const text = (data, keys) => keys.map((key) => data[key]).find(
  (value) => value !== null && value !== undefined && String(value).trim() && String(value) !== '0',
);

exports.startScholarshipTracking = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please login first.');
  const scholarshipId = String(request.data?.scholarshipId || '').trim();
  if (!scholarshipId) throw new HttpsError('invalid-argument', 'Scholarship id is required.');

  const uid = request.auth.uid;
  const userRef = db.collection('users').doc(uid);
  const scholarshipRef = db.collection('scholarships').doc(scholarshipId);
  const [userSnapshot, scholarshipSnapshot, documentsSnapshot] = await Promise.all([
    userRef.get(), scholarshipRef.get(), userRef.collection('documents').get(),
  ]);
  if (!scholarshipSnapshot.exists) throw new HttpsError('not-found', 'Scholarship not found.');
  const profile = userSnapshot.data() || {};
  const expiry = profile.subscriptionExpiry?.toDate?.();
  if (String(profile.subscriptionStatus || '').toLowerCase() !== 'premium' || (expiry && expiry <= new Date())) {
    throw new HttpsError('permission-denied', 'Premium subscription is required to apply.');
  }
  const documents = Object.fromEntries(documentsSnapshot.docs.map((doc) => [doc.id, doc.data()]));
  const missing = Object.entries(REQUIRED_FIELDS)
    .filter(([, keys]) => !text(profile, keys))
    .map(([label]) => label);
  for (const [id, label] of [['cv', 'CV'], ['sop', 'SOP'], ['transcript', 'Transcript']]) {
    if (!text(documents[id] || {}, ['fileName', 'downloadUrl'])) missing.push(label);
  }
  if (missing.length) throw new HttpsError('failed-precondition', 'Profile is incomplete.', { missing });

  const applicationId = `${uid}_${scholarshipId}`;
  const applicationRef = db.collection('applications').doc(applicationId);
  const userApplicationRef = userRef.collection('applications').doc(applicationId);
  const scholarship = scholarshipSnapshot.data() || {};
  const outcome = await db.runTransaction(async (transaction) => {
    if ((await transaction.get(applicationRef)).exists) return { created: false };
    const checklist = Object.fromEntries(['passport', 'cv', 'sop', 'recommendationLetter', 'transcript', 'ielts', 'researchProposal'].map((id) => [id, false]));
    const record = {
      applicationId, userId: uid, scholarshipId,
      scholarshipTitle: String(scholarship.title || ''), university: String(scholarship.university || ''),
      country: String(scholarship.country || ''), deadline: scholarship.deadline || null,
      status: 'IN_PROGRESS', currentStep: 0, progress: 0, checklist,
      appliedDate: FieldValue.serverTimestamp(), lastUpdated: FieldValue.serverTimestamp(),
      notes: '', adminNotes: '', reviewedBy: null, reviewedAt: null,
      profileSnapshot: profile, documentsSnapshot: documents,
      title: String(scholarship.title || ''), degree: String(scholarship.degree || ''), image: String(scholarship.image || ''),
    };
    transaction.set(applicationRef, record);
    transaction.set(userApplicationRef, record);
    transaction.update(scholarshipRef, { applicationCount: FieldValue.increment(1) });
    return { created: true };
  });
  return { applicationId, ...outcome, officialUrl: String(scholarship.link || '') };
});


exports.updateScholarshipTracking = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please login first.');
  const applicationId = String(request.data?.applicationId || '').trim();
  const action = String(request.data?.action || '').trim();
  if (!applicationId || !['submitted', 'checklist'].includes(action)) {
    throw new HttpsError('invalid-argument', 'Invalid tracking update.');
  }
  const uid = request.auth.uid;
  const applicationRef = db.collection('applications').doc(applicationId);
  const userRef = db.collection('users').doc(uid).collection('applications').doc(applicationId);
  const updates = { lastUpdated: FieldValue.serverTimestamp() };
  if (action === 'submitted') {
    Object.assign(updates, { status: 'SUBMITTED', currentStep: 2, progress: 30, submittedAt: FieldValue.serverTimestamp() });
  } else {
    const checklist = request.data?.checklist;
    if (!checklist || typeof checklist !== 'object') throw new HttpsError('invalid-argument', 'Checklist is required.');
    const allowed = new Set(['passport', 'cv', 'sop', 'recommendationLetter', 'transcript', 'ielts', 'researchProposal']);
    const clean = Object.fromEntries(Object.entries(checklist).filter(([key]) => allowed.has(key)).map(([key, value]) => [key, value === true]));
    const complete = Object.values(clean).filter(Boolean).length;
    Object.assign(updates, { checklist: clean, progress: Math.min(25, Math.round((complete / 7) * 25)), currentStep: complete === 7 ? 1 : 0 });
  }
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(applicationRef);
    if (!snapshot.exists || snapshot.data().userId !== uid) throw new HttpsError('not-found', 'Application not found.');
    transaction.update(applicationRef, updates);
    transaction.update(userRef, updates);
  });
  return { ok: true };
});
