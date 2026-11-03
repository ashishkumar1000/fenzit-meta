/**
 * Phase 2 v2: drive the seeded jobs through their workflows (as the assigned
 * technicians), add photos, check three employees in, file leave.
 * Job IDs come from the phase-1 logs; nothing new is created here.
 */
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';

const API = 'https://api.fenzit.com/api/v1';
const PHOTO = '/Users/admin/workspace/fenzit-meta/artifacts/play-listing/graphics/job-ac-service.jpg';

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

async function stepsFor(token: string, jobId: string): Promise<{ key: string; label: string }[]> {
  const d = await api('GET', `/jobs/${jobId}`, token);
  if (d.status !== 200) throw new Error(`job get: ${d.status} ${JSON.stringify(d.json)}`);
  const steps = d.json?.workflowTemplate?.steps ?? [];
  return steps.map((s: any) => ({ key: s.key, label: s.label }));
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
  const uploadId = j.uploadId ?? j.id;
  const uploadUrl = j.uploadUrl ?? j.url;
  const put = await fetch(uploadUrl, {
    method: 'PUT',
    body: fs.readFileSync(PHOTO),
    headers: { 'content-type': 'image/jpeg' },
  });
  const confirm = await api(
    'POST',
    `/jobs/${jobId}/attachments/${uploadId}/confirm`,
    token,
    { sizeBytes },
    { 'x-idempotency-key': crypto.randomUUID() },
  );
  console.log('  photo upload put=%d confirm=%d', put.status, confirm.status);
}

const GURGAON = { latitude: 28.4994, longitude: 77.0835 };

async function completeJob(token: string, name: string, jobId: string, photoStepKey: string | null): Promise<void> {
  const steps = await stepsFor(token, jobId);
  console.log('%s steps: %j', name, steps.map((s) => s.key));
  for (const s of steps) {
    if (s.key === photoStepKey) await uploadPhoto(token, jobId);
    const r = await api('POST', `/jobs/${jobId}/workflow`, token, { step: s.key, ...GURGAON, accuracy: 15 }, { 'x-idempotency-key': crypto.randomUUID() });
    console.log('  %s %s -> %d %s', name, s.key, r.status, r.status === 200 ? '' : JSON.stringify(r.json).slice(0, 140));
  }
}

async function main() {
  const TAPS = 'e74a768a-3dbe-4255-b4f2-41c509aa409c'; // JB-0001, Arjun, yesterday
  const LOBBY = '2dc6fd59-0288-4ecc-a45b-6165cd0a6e08'; // urgent hotel AC, Ramesh, yesterday
  const QUARTERLY = 'd34d602e-d455-4a02-ae87-3c1bade0c540'; // Ramesh, today 11:30

  const arjun = await login('+91', '9810022333');
  const ramesh = await login('+91', '9810022331');
  const priya = await login('+91', '9810022332');
  const sunita = await login('+91', '9810022334');
  const owner = await login('+91', '9810012345');

  // Yesterday's jobs -> completed (photos land on the photo step).
  await completeJob(arjun.token, 'taps', TAPS, null);
  await completeJob(ramesh.token, 'lobby', LOBBY, 'photos_uploaded');

  // Today's quarterly job -> in progress (one step), photo already attached.
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
    console.log('check-in %s -> %d %s', phone, res.status, res.status === 201 ? '' : JSON.stringify(res.json).slice(0, 160));
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
  console.log('leave pending -> %d %s', l1.status, JSON.stringify(l1.json).slice(0, 200));
  const l2 = await api('POST', '/attendance/leave/on-behalf', owner.token, {
    employeeId: '7da41c9a-ab4e-46bf-a08e-f796f15ed2c1',
    startDate: isoDay(3),
    endDate: isoDay(3),
    part: 'first_half',
    reason: 'Medical check-up at the clinic.',
  });
  console.log('leave approve-me -> %d %s', l2.status, JSON.stringify(l2.json).slice(0, 200));
  const leaveId2 = (l2.json as any)?.id ?? (l2.json as any)?.leave?.id;
  if (leaveId2) {
    const approved = await api('POST', `/attendance/leave/${leaveId2}/approve`, owner.token, {});
    console.log('leave approved -> %d', approved.status);
  }
  console.log('PHASE 2 DONE');
}

main().catch((e) => {
  console.error('PHASE 2 FAILED:', e.message ?? e);
  process.exit(1);
});
