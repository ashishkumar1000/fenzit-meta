/**
 * Phase 4 (resume): check-ins with the full AD-20 capture, Priya's pending
 * leave (applied by her), Arjun's on-behalf approved leave.
 */
import * as crypto from 'node:crypto';

const API = 'https://api.fenzit.com/api/v1';

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

async function main() {
  const ramesh = await login('+91', '9810022331');
  const priya = await login('+91', '9810022332');
  const sunita = await login('+91', '9810022334');
  const owner = await login('+91', '9810012345');

  const checkIn = async (token: string, phone: string, lat: number, lng: number, acc: number) => {
    const res = await api(
      'POST',
      '/attendance/me/check-in',
      token,
      { latitude: lat, longitude: lng, accuracyM: acc, fixAgeMs: 8000, provider: 'fused', mocked: false },
      { 'x-idempotency-key': crypto.randomUUID() },
    );
    console.log('check-in %s -> %d %s', phone, res.status, res.status === 201 ? '' : JSON.stringify(res.json).slice(0, 220));
  };
  await checkIn(ramesh.token, '9810022331', 28.4996, 77.0837, 12);
  await checkIn(priya.token, '9810022332', 28.4993, 77.0833, 18);
  await checkIn(sunita.token, '9810022334', 28.4991, 77.0831, 25);

  // Priya applies herself -> pending in the owner's queue.
  const isoDay = (offset: number) => new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);
  const mine = await api(
    'POST',
    '/attendance/me/leave',
    priya.token,
    { startDate: isoDay(1), endDate: isoDay(1), part: 'full_day', reason: 'Family function at home in Meerut.' },
    { 'x-idempotency-key': crypto.randomUUID() },
  );
  console.log('priya leave -> %d %s', mine.status, JSON.stringify(mine.json).slice(0, 220));

  // Owner files on Arjun's behalf -> approved immediately.
  const behalf = await api(
    'POST',
    '/attendance/leave/on-behalf',
    owner.token,
    { employeeId: '7da41c9a-ab4e-46bf-a08e-f796f15ed2c1', startDate: isoDay(3), endDate: isoDay(3), part: 'first_half', reason: 'Medical check-up at the clinic.' },
    { 'x-idempotency-key': crypto.randomUUID() },
  );
  console.log('arjun leave (approved) -> %d %s', behalf.status, JSON.stringify(behalf.json).slice(0, 220));
  console.log('PHASE 4 DONE');
}

main().catch((e) => {
  console.error('PHASE 4 FAILED:', e.message ?? e);
  process.exit(1);
});
