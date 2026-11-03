import * as crypto from 'node:crypto';
const API = 'https://api.fenzit.com/api/v1';
type Json = Record<string, unknown>;
async function api(method: string, path: string, token: string | null, body?: Json, extra: Record<string, string> = {}) {
  const res = await fetch(API + path, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}), ...extra }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  return { status: res.status, json: text ? JSON.parse(text) : null };
}
async function login(phone: string) {
  const s = await api('POST', '/auth/otp/send', null, { countryCode: '+91', phoneNumber: phone });
  if (s.status !== 200) throw new Error('send ' + JSON.stringify(s.json));
  const v = await api('POST', '/auth/otp/verify', null, { otpSessionId: (s.json as any).otp_session_id, otpCode: '1039' });
  if (v.status !== 200) throw new Error('verify ' + JSON.stringify(v.json));
  return (v.json as any).token as string;
}
async function main() {
  const owner = await login('9810012345');
  const vikram = await login('9810022335');
  const officeId = 'aa5ba393-63f6-4913-b414-e23fd2340d45';
  const enr = await api('PUT', '/attendance/enrolments/297623c1-8197-418f-a634-b3a98116d144', owner.token, { officeId });
  console.log('enrol vikram ->', enr.status, JSON.stringify(enr.json).slice(0, 120));
  const isoDay = (o: number) => new Date(Date.now() + o * 86400000).toISOString().slice(0, 10);
  const leave = await api(
    'POST',
    '/attendance/me/leave',
    vikram,
    { startDate: isoDay(1), endDate: isoDay(1), part: 'full_day', reason: 'Sister\u2019s wedding in Jaipur.' },
    { 'x-idempotency-key': crypto.randomUUID() },
  );
  console.log('vikram leave ->', leave.status, JSON.stringify(leave.json).slice(0, 220));
}
main().catch((e) => { console.error('FAILED:', e.message ?? e); process.exit(1); });
