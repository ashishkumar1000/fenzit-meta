/**
 * Seeds a realistic demo company on the production API for Play Store
 * screenshots. Run with: bun artifacts/play-listing/seed-demo.ts
 *
 * Mock tenant: "Sparkle Facility Services" (owner +91 9810012345, sign-in
 * uses the flag-gated pre-release master OTP 1039 — no real SMS involved).
 * Every person and number below is fictional.
 */
const API = 'https://api.fenzit.com/api/v1';
import * as crypto from 'node:crypto';

type Json = Record<string, unknown>;

async function api(
  method: string,
  path: string,
  token: string | null,
  body?: Json,
): Promise<{ status: number; json: any }> {
  const res = await fetch(API + path, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json: any = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text.slice(0, 200) };
  }
  return { status: res.status, json };
}

async function login(countryCode: string, phoneNumber: string) {
  const send = await api('POST', '/auth/otp/send', null, { countryCode, phoneNumber });
  if (send.status !== 200) throw new Error(`otp/send ${phoneNumber}: ${send.status} ${JSON.stringify(send.json)}`);
  const sessionId = (send.json as any).otp_session_id ?? (send.json as any).otpSessionId;
  const verify = await api('POST', '/auth/otp/verify', null, { otpSessionId: sessionId, otpCode: '1039' });
  if (verify.status !== 200) throw new Error(`otp/verify ${phoneNumber}: ${verify.status} ${JSON.stringify(verify.json)}`);
  return verify.json as { token: string; user: { userId: string; tenantId: string | null; role: string | null; name: string | null } };
}

async function main() {
  const ownerPhone = { countryCode: '+91', phoneNumber: '9810012345' };
  const memberTokens: Record<string, string> = {};
  const memberIds: Record<string, string> = {};

  // 1. Owner login (creates the user on first sign-in; no tenant yet).
  const owner1 = await login(ownerPhone.countryCode, ownerPhone.phoneNumber);
  console.log('owner userId=%s tenant=%s role=%s', owner1.user.userId, owner1.user.tenantId, owner1.user.role);

  // 2. Company (idempotent upsert; returns a fresh token carrying the tenant).
  let owner = owner1;
  if (!owner1.user.tenantId) {
    const created = await api('POST', '/auth/company', owner1.token, {
      name: 'Rohit Sharma',
      companyName: 'Sparkle Facility Services',
      stateCode: 'HR',
      address: 'Plot 21, Udyog Vihar, Gurugram',
    });
    if (created.status !== 200 && created.status !== 201) {
      throw new Error(`company create: ${created.status} ${JSON.stringify(created.json)}`);
    }
    const t = created.json as { token: string; tenant: { id: string; name: string } };
    console.log('company created %s (%s)', t.tenant.name, t.tenant.id);
    const owner2 = await login(ownerPhone.countryCode, ownerPhone.phoneNumber);
    owner = { token: owner2.token, user: owner2.user };
  }
  console.log('owner tenant=%s role=%s', owner.user.tenantId, owner.user.role);

  // 3. Skills catalog (global, read-only).
  const skills = await api('GET', '/skills', owner.token);
  if (skills.status !== 200) throw new Error(`skills: ${skills.status} ${JSON.stringify(skills.json)}`);
  const skillList = (skills.json as { skills: { id: string; name: string }[] }).skills;
  console.log('skills: %s', skillList.map((s) => s.name).join(', '));
  const byName = (needle: string) => {
    const s = skillList.find((x) => x.name.toLowerCase().includes(needle.toLowerCase()));
    if (!s) throw new Error(`skill not found: ${needle}`);
    return s.id;
  };
  const acRepair = byName('ac general service');
  const plumbing = byName('pipe leak');
  const electrical = byName('electrical wiring');
  const cleaning = byName('deep home cleaning');
  const pest = byName('general pest');

  // 4. Invite the team (fictional people, fictional numbers).
  const team = [
    { countryCode: '+91', phoneNumber: '9810022331', name: 'Ramesh Kumar', role: 'employee', skillIds: [acRepair] },
    { countryCode: '+91', phoneNumber: '9810022332', name: 'Priya Singh', role: 'employee', skillIds: [cleaning] },
    { countryCode: '+91', phoneNumber: '9810022333', name: 'Arjun Patel', role: 'employee', skillIds: [plumbing, electrical] },
    { countryCode: '+91', phoneNumber: '9810022334', name: 'Sunita Devi', role: 'employee', skillIds: [cleaning, pest] },
    { countryCode: '+91', phoneNumber: '9810022335', name: 'Vikram Joshi', role: 'employee', skillIds: [electrical] },
  ];
  for (const m of team) {
    const inv = await api('POST', '/auth/invite', owner.token, m as Json);
    if (inv.status === 201 || inv.status === 200) {
      console.log('invited %s (%s)', m.name, m.phoneNumber);
    } else if (String(inv.json?.message ?? '').toLowerCase().includes('already')) {
      console.log('already invited %s', m.name);
    } else {
      console.log('invite %s -> %d %j', m.name, inv.status, inv.json);
    }
    // First sign-in activates the invited membership.
    const act = await login(m.countryCode, m.phoneNumber);
    memberTokens[m.phoneNumber] = act.token;
    memberIds[m.phoneNumber] = act.user.userId;
    console.log('  activated %s userId=%s', m.name, act.user.userId);
  }

  // 5. Members list for technician IDs.
  const members = await api('GET', '/members', owner.token);
  if (members.status !== 200) throw new Error(`members: ${members.status} ${JSON.stringify(members.json)}`);
  const list = (members.json as any).members ?? members.json;
  console.log(
    'members: %s',
    (list as any[]).map((x) => `${x.name}:${x.role}:${x.userId ?? x.id}`).join(' | '),
  );
  const memberByPhone = (phone: string) => {
    const m = (list as any[]).find((x) => String(x.phoneNumber ?? x.phone_number).endsWith(phone.slice(-4)));
    if (!m) throw new Error(`member not found for ${phone}`);
    return m.userId ?? m.id;
  };
  const ramesh = memberByPhone('9810022331');
  const priya = memberByPhone('9810022332');
  const arjun = memberByPhone('9810022333');
  const sunita = memberByPhone('9810022334');
  const vikram = memberByPhone('9810022335');

  // 6. Customers.
  const customers = [
    { countryCode: '+91', phoneNumber: '9811133441', name: 'Grand Plaza Hotel' },
    { countryCode: '+91', phoneNumber: '9811133442', name: 'GreenLeaf Coworks' },
    { countryCode: '+91', phoneNumber: '9811133443', name: 'Sunrise Residency' },
    { countryCode: '+91', phoneNumber: '9811133444', name: 'Metro Mall Services' },
  ];
  const customerIds: Record<string, string> = {};
  for (const c of customers) {
    const r = await api('POST', '/customers', owner.token, c as Json);
    const j = r.json as any;
    customerIds[c.name] = j?.customer?.id ?? j?.id;
    console.log('customer %s -> %d %s', c.name, r.status, customerIds[c.name] ?? JSON.stringify(j)?.slice(0, 120));
  }

  // 7. Jobs across statuses and days (today is the anchor).
  const day = (offset: number, hour: number, min = 0) => {
    const d = new Date(Date.now() + offset * 86400000);
    d.setHours(hour, min, 0, 0);
    return d.toISOString();
  };
  const jobs = [
    { newCustomer: { countryCode: '+91', phoneNumber: '9811133445', name: 'Orchid Apartments' }, serviceLocation: 'Tower B, Orchid Apartments, Sector 45', skillId: plumbing, scheduledStart: day(-1, 10), scheduledEnd: day(-1, 12), technicianId: arjun, priority: 'normal', description: 'Two bathroom taps leaking; replace washers and check the geyser inlet.' },
    { customerId: customerIds['Grand Plaza Hotel'], serviceLocation: 'Lobby wing, Grand Plaza Hotel', skillId: acRepair, scheduledStart: day(-1, 15), scheduledEnd: day(-1, 17), technicianId: ramesh, priority: 'high', description: 'Three lobby AC units not cooling; clean filters and refill gas.' },
    { customerId: customerIds['GreenLeaf Coworks'], serviceLocation: '2nd floor, GreenLeaf Coworks', skillId: cleaning, scheduledStart: day(0, 9), scheduledEnd: day(0, 11), technicianId: priya, priority: 'normal', description: 'Deep clean of the pantry and meeting rooms after the event.' },
    { customerId: customerIds['Grand Plaza Hotel'], serviceLocation: 'Rooms 401-410, Grand Plaza Hotel', skillId: acRepair, scheduledStart: day(0, 11, 30), scheduledEnd: day(0, 13, 30), technicianId: ramesh, priority: 'normal', description: 'Quarterly AC service for the fourth-floor rooms.' },
    { newCustomer: { countryCode: '+91', phoneNumber: '9811133446', name: 'City Library' }, serviceLocation: 'Reading hall, City Library, Sector 14', skillId: electrical, scheduledStart: day(0, 14), scheduledEnd: day(0, 16), technicianId: vikram, priority: 'high', description: 'Two tube lights flickering in the reading hall; check the ballasts.' },
    { customerId: customerIds['Sunrise Residency'], serviceLocation: 'Block A, Sunrise Residency', skillId: pest, scheduledStart: day(0, 16), scheduledEnd: day(0, 17), technicianId: sunita, priority: 'normal', description: 'Monthly pest control for the common areas and basement.' },
    { customerId: customerIds['Metro Mall Services'], serviceLocation: 'Food court, Metro Mall', skillId: plumbing, scheduledStart: day(1, 10), scheduledEnd: day(1, 12), technicianId: arjun, priority: 'normal', description: 'Food-court drain smells; inspect and clear the floor traps.' },
    { customerId: customerIds['GreenLeaf Coworks'], serviceLocation: '1st floor, GreenLeaf Coworks', skillId: electrical, scheduledStart: day(1, 15), scheduledEnd: day(1, 16), technicianId: vikram, priority: 'low', description: 'Add two power sockets near the new desk row.' },
  ];
  const createdJobs: { id: string; label: string }[] = [];
  for (const j of jobs) {
    const r = await api('POST', '/jobs', owner.token, j as Json);
    const id = (r.json as any)?.id ?? (r.json as any)?.job?.id;
    createdJobs.push({ id, label: String(j.description).slice(0, 40) });
    console.log('job -> %d %s %s', r.status, id ?? JSON.stringify(r.json).slice(0, 160), j.description.slice(0, 30));
  }

  // 8. Workflow progress: complete yesterday's two jobs, advance today's first.
  const wf = async (idx: number) => {
    const j = createdJobs[idx];
    if (!j?.id) return;
    const r = await api('POST', `/jobs/${j.id}/workflow`, owner.token, {});
    console.log('workflow %s -> %d', j.id.slice(0, 8), r.status);
    return r;
  };
  for (const idx of [0, 1]) await wf(idx);
  for (const idx of [0, 1]) await wf(idx);
  await wf(3);

  // 9. Attendance: setup wizard, office, weekly off, holiday, enrolments.
  const started = await api('POST', '/attendance/setup', owner.token, {});
  console.log('attendance setup start -> %d', started.status);
  for (const step of ['offices', 'timings', 'weekly_off', 'holidays', 'employees']) {
    await api('PATCH', '/attendance/setup', owner.token, { currentStep: step });
  }
  const office = await api('POST', '/attendance/offices', owner.token, {
    name: 'Sparkle Hub, Udyog Vihar',
    formattedAddress: 'Plot 21, Udyog Vihar Phase III, Gurugram',
    latitude: 28.4994,
    longitude: 77.0835,
    radiusM: 150,
    startTime: '09:00',
    endTime: '18:00',
    fullDayHours: 8,
    halfDayHours: 4,
    lateCutoffMinutes: 15,
  });
  const officeId = (office.json as any)?.office?.id ?? (office.json as any)?.id;
  console.log('office -> %d %s', office.status, officeId ?? JSON.stringify(office.json).slice(0, 160));
  if (!officeId) throw new Error('no office id');
  const wfo = await api('PUT', '/attendance/weekly-offs', owner.token, { days: [7] });
  console.log('weekly off -> %d', wfo.status);
  const holiday = await api('POST', '/attendance/holidays', owner.token, {
    name: 'Guru Nanak Jayanti',
    date: '2026-11-24',
  });
  console.log('holiday -> %d', holiday.status);
  for (const phone of ['9810022331', '9810022332', '9810022333', '9810022334']) {
    const enr = await api('PUT', `/attendance/enrolments/${memberIds[phone]}`, owner.token, {
      officeId,
    });
    console.log('enrol %s -> %d', phone, enr.status);
  }
  const complete = await api('POST', '/attendance/setup/complete', owner.token, {});
  console.log('setup complete -> %d %j', complete.status, complete.json).valueOf();

  // 10. Check-ins (inside the office geofence). Server records real time —
  // run this in the morning for believable "late" states.
  const randomKey = () => crypto.randomUUID();
  const checkIn = async (phone: string, lat: number, lng: number, acc: number) => {
    const r = await api(
      'POST',
      '/attendance/me/check-in',
      memberTokens[phone],
      { latitude: lat, longitude: lng, accuracyM: acc, provider: 'fused', mocked: false },
    );
    console.log('check-in %s -> %d %j', phone, r.status, r.json).valueOf();
    return r;
  };
  await checkIn('9810022331', 28.4996, 77.0837, 12);
  await checkIn('9810022332', 28.4993, 77.0833, 18);
  await checkIn('9810022334', 28.4991, 77.0831, 25);

  // 11. Leave: one pending in the owner queue, one already approved.
  const isoDay = (offset: number) =>
    new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);
  const l1 = await api('POST', '/attendance/leave/on-behalf', owner.token, {
    employeeId: memberIds['9810022332'],
    startDate: isoDay(1),
    endDate: isoDay(1),
    part: 'full_day',
    reason: 'Family function at home in Meerut.',
  });
  const l2 = await api('POST', '/attendance/leave/on-behalf', owner.token, {
    employeeId: memberIds['9810022333'],
    startDate: isoDay(3),
    endDate: isoDay(3),
    part: 'first_half',
    reason: 'Medical check-up at the clinic.',
  });
  console.log('leave filed -> %d %d', l1.status, l2.status);
  const leaveId2 = (l2.json as any)?.id ?? (l2.json as any)?.leave?.id;
  if (leaveId2) {
    const approved = await api('POST', `/attendance/leave/${leaveId2}/approve`, owner.token, {});
    console.log('leave approved -> %d', approved.status);
  }
  console.log('done');
}

main().catch((e) => {
  console.error('SEED FAILED:', e.message ?? e);
  process.exit(1);
});
