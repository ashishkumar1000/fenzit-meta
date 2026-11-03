/**
 * Phase 3 (resume): finish the lobby job (photo + remaining steps), start the
 * quarterly job, check three employees in, file leave. Safe to re-run.
 */
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';

const API = 'https://api.fenzit.com/api/v1';
const PHOTO = '/Users/admin/workspace/fenzit-meta/artifacts/play-listing/graphics/job-ac-service.jpg';
const LOBBY = '2dc6fd59-0288-4ecc-a45b-6165cd0a6e08';
const QUARTERLY = 'd34d602e-d455-4a02-ae87-3c1bade0c540';
const GURGAON = { latitude: 28.4994, longitude: 77.0835 };

type Json = Record<string, unknown>;

async function api(
  method: string,
  path: string,
  token: string | null,
  body?: Json,
  extraHeaders: Record<string, string> = {},
): Promise<{ status: number; json: any }> {
  const res = await fetch(API + path, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...extraHeaders,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json: any = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text.slice(0, 300) };
  }
  return { status: res.status, json };
}

async function login(countryCode: string, phoneNumber: string) {
  const send = await api('POST', '/auth/otp/send', null, { countryCode, phoneNumber });
  if (send.status !== 200) throw new Error(`otp/send ${phoneNumber}: ${send.status} ${JSON.stringify(send.json)}`);
  const sessionId = (send.json as any).otp_session_id ?? (send.json as any).otpSessionId;
  const verify = await api('POST', '/auth/otp/verify', null, { otpSessionId: sessionId, otpCode: '1039' });
  if (verify.status !== 200) throw new Error(`otp/verify ${phoneNumber}: ${verify.status} ${JSON.stringify(verify.json)}`);
  return verify.json as { token: string };
}

async function uploadPhoto(token: string, jobId: string): Promise<void> {
  const sizeBytes = fs.statSync(PHOTO).size;
  const req = await api(
    'POST',
    `/jobs/${jobId}/attachments`,
    token,
    { filename: 'ac-service.jpg', mimeType: 'image/jpeg', attachmentType: 'photo', sizeBytes },
    { 'x-idempotency-key': crypto.randomUUID() },
  );
  if (req.status !== 200) throw new Error(`attachment request: ${req.status} ${JSON.stringify(req.json)}`);
  const j = req.json as any;
  const put = await fetch(j.presignedPutUrl, {
    method: 'PUT',
    body: fs.readFileSync(PHOTO),
    headers: { 'content-type': 'image/jpeg' },
  });
  const confirm = await api(
    'POST',
    `/jobs/${jobId}/attachments/${j.uploadId}/confirm`,
    token,
    { sizeBytes },
    { 'x-idempotency-key': crypto.randomUUID() },
  );
  console.log('  photo put=%d confirm=%d', put.status, confirm.status);
}

async function main() {
  const ramesh = await login('+91', '9810022331');
  const priya = await login('+91', '9810022332');
  const sunita = await login('+91', '9810022334');
  const owner = await login('+91', '9810012345');

  // Lobby job: already at in_progress. Photo first, then the remaining steps.
  await uploadPhoto(ramesh.token, LOBBY);
  for (const key of ['photos_uploaded', 'signature_captured', 'completed']) {
    const r = await api('POST', `/jobs/${LOBBY}/workflow`, ramesh.token, { step: key, ...GURGAON, accuracy: 15 }, { 'x-idempotency-key': crypto.randomUUID() });
    console.log('lobby %s -> %d %s', key, r.status, r.status === 200 ? '' : JSON.stringify(r.json).slice(0, 140));
  }

  // Quarterly job: first step -> in progress for today's board.
  const r = await api('POST', `/jobs/${QUARTERLY}/workflow`, ramesh.token, { step: 'on_my_way', ...GURGAON, accuracy: 15 }, { 'x-idempotency-key': crypto.randomUUID() });
  console.log('quarterly on_my_way -> %d %s', r.status, r.status === 200 ? '' : JSON.stringify(r.json).slice(0, 160));

  // Attendance check-ins.
  const checkIn = async (token: string, phone: string, lat: number, lng: number, acc: number) => {
    const res = await api(
      'POST',
      '/attendance/me/check-in',
      token,
      { latitude: lat, longitude: lng, accuracyM: acc, provider: 'fused', mocked: false },
      { 'x-idempotency-key': crypto.randomUUID() },
    );
    console.log('check-in %s -> %d %s', phone, res.status, res.status === 201 ? '' : JSON.stringify(res.json).slice(0, 200));
  };
  await checkIn(ramesh.token, '9810022331', 28.4996, 77.0837, 12);
  await checkIn(priya.token, '9810022332', 28.4993, 77.0833, 18);
  await checkIn(sunita.token, '9810022334', 28.4991, 77.0831, 25);

  // Leave: one pending, one approved.
  const isoDay = (offset: number) => new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);
  const l1 = await api('POST', '/attendance/leave/on-behalf', owner.token, {
    employeeId: 'ffd890f4-d618-4631-90ea-bc0179bd5a37',
    startDate: isoDay(1),
    endDate: isoDay(1),
    part: 'full_day',
    reason: 'Family function at home in Meerut.',
  });
  console.log('leave pending -> %d %s', l1.status, JSON.stringify(l1.json).slice(0, 220));
  const l2 = await api('POST', '/attendance/leave/on-behalf', owner.token, {
    employeeId: '7da41c9a-ab4e-46bf-a08e-f796f15ed2c1',
    startDate: isoDay(3),
    endDate: isoDay(3),
    part: 'first_half',
    reason: 'Medical check-up at the clinic.',
  });
  console.log('leave to-approve -> %d %s', l2.status, JSON.stringify(l2.json).slice(0, 220));
  const leaveId2 = (l2.json as any)?.id ?? (l2.json as any)?.leave?.id;
  if (leaveId2) {
    const approved = await api('POST', `/attendance/leave/${leaveId2}/approve`, owner.token, {});
    console.log('leave approved -> %d', approved.status);
  }
  console.log('PHASE 3 DONE');
}

main().catch((e) => {
  console.error('PHASE 3 FAILED:', e.message ?? e);
  process.exit(1);
});
