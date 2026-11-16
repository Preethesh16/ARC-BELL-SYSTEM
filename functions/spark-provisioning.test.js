const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {test} = require('node:test');

const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const dbHost = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
if (!/^127\.0\.0\.1:\d+$/.test(authHost || '') || !/^127\.0\.0\.1:\d+$/.test(dbHost || '')) {
  throw new Error('Use the local demo emulators only');
}
const password = 'OnlyForSimulation2026!';
async function signup(email) {
  const res = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({email, password, returnSecureToken: true}),
  });
  return {status: res.status, ...await res.json()};
}
async function db(path, auth, body, options = {}) {
  const u = new URL(`http://${dbHost}/${path}.json`);
  u.searchParams.set('ns', 'demo-college-bell-default-rtdb');
  if (auth && auth !== 'owner') u.searchParams.set('auth', auth);
  const res = await fetch(u, {
    method: body === undefined ? 'GET' : 'PUT',
    headers: {'Content-Type': 'application/json', ...(auth === 'owner' ? {Authorization: 'Bearer owner'} : {}), ...options},
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return {status: res.status, value: await res.json()};
}

test('Spark signup, rules and legacy isolation; no bell writes', async () => {
  const email = (name) => `${name}-${randomUUID()}@example.test`;
  const address = email('physics');
  const [admin, dev, maths, newUser, unassigned] = await Promise.all(
    [email('admin'), email('dev'), email('maths'), address, email('unassigned')].map(signup)
  );
  for (const user of [admin, dev, maths, newUser, unassigned]) assert.equal(user.status, 200);
  const at = admin.idToken; const dt = dev.idToken; const mt = maths.idToken;
  const pt = newUser.idToken; const ut = unassigned.idToken;
  const legacy = {name: 'Mathematics', mode: 'college', deviceStatus: {appliedMode: 'college'}};
  assert.equal((await db('departments/icbs', 'owner', legacy)).status, 200);
  assert.equal((await db(`users/${admin.localId}`, 'owner', {role: 'admin'})).status, 200);
  assert.equal((await db(`users/${dev.localId}`, 'owner', {role: 'superadmin'})).status, 200);
  const mathsPath = `users/${maths.localId}`;
  assert.equal((await db(mathsPath, 'owner', {role: 'secretary', departments: {icbs: true}})).status, 200);
  assert.equal((await db('sparkProvisioning', at)).status, 200);
  assert.equal((await db('sparkProvisioning', mt)).status, 401);
  assert.equal((await db('departments', 'owner')).status, 200);
  assert.equal((await db('departments/icbs', mt)).status, 200);
  assert.equal((await db('departments', mt)).status, 401);
  assert.equal((await db(mathsPath+'/role', mt, 'admin')).status, 401);
  assert.equal((await db(mathsPath, at, {role:'secretary', departments:{dept1:true}, managedDepartment:'dept1'})).status, 401);

  const generation = '01'.repeat(16);
  const empty = {name:'Physics', mode:'college', generation, config:{ringDurationSec:5,timezone:'IST'}};
  const create = {'If-Match':'null_etag'};
  const [one, two] = await Promise.all([db('departments/dept1', at, empty, create), db('departments/dept1', dt, empty, create)]);
  assert.equal([one, two].filter(r => r.status === 200).length, 1);
  assert.equal((await db('departments/dept2', dt, {...empty,name:'Chemistry'}, create)).status, 200);
  assert.equal((await db('departments/dept2/name', dt, 'Applied Chemistry')).status, 200);
  assert.equal((await db('departments/dept1', at, empty)).status, 401);
  assert.equal((await db('departments/icbs', at, empty)).status, 401);
  assert.equal((await db('departments/dept3', mt, empty)).status, 401);
  assert.equal((await db('departments/icbs', pt)).status, 401);
  assert.equal((await db('departments/dept1', ut)).status, 401);

  const target = `users/${newUser.localId}`;
  const assignment = {role: 'secretary', departments: {dept1:true}, managedDepartment:'dept1', departmentGeneration:generation};
  assert.equal((await db(target, pt, assignment)).status, 401);
  assert.notEqual((await db(target, at, {...assignment, role:'admin'})).status, 200);
  assert.notEqual((await db(target, at, {...assignment, departmentGeneration:'ff'.repeat(16)})).status, 200);
  assert.notEqual((await db(target, at, {...assignment, departments:{dept1:true,icbs:true}})).status, 200);
  assert.equal((await db(target, at, assignment)).status, 200);
  assert.deepEqual((await db(target, pt)).value, assignment);
  assert.equal((await db(target+'/departments/dept2', pt, true)).status, 401);
  assert.equal((await db('departments/dept1', pt)).status, 200);
  assert.equal((await db('departments/dept1/name', pt, 'Not allowed')).status, 401);
  assert.equal((await db('departments/dept1/schedules/college/times', pt, [540])).status, 200);
  assert.equal((await db('departments/dept2', pt)).status, 401);
  assert.equal((await db('departments/icbs/mode', pt, 'exam')).status, 401);
  assert.deepEqual((await db('departments/icbs', 'owner')).value, legacy);
  assert.equal((await signup(address)).error.message, 'EMAIL_EXISTS');

  const marker = {deleted: true};
  const [header, payload] = at.split('.');
  const oldClaims = JSON.parse(Buffer.from(payload, 'base64url'));
  oldClaims.auth_time -= 180;
  const stale = `${header}.${Buffer.from(JSON.stringify(oldClaims)).toString('base64url')}.`;
  assert.equal((await db('sparkProvisioning', stale)).status, 200);
  assert.equal((await db('departments/dept1', stale, marker)).status, 401);
  assert.equal((await db('departments/dept1', pt, marker)).status, 401);
  assert.equal((await db('departments/icbs', at, marker)).status, 401);
  assert.equal((await db('departments/dept1', at, {...marker, name: 'Physics'})).status, 401);
  assert.equal((await db('departments/dept1', at, marker)).status, 200);
  assert.deepEqual((await db('departments/dept1', at)).value, marker);
  assert.equal((await db('departments/dept1', pt)).status, 401);
  assert.equal((await db('departments/dept1/mode', pt, 'exam')).status, 401);
  assert.equal((await db('departments/dept1', at, empty, create)).status >= 400, true);
  // A project operator cleared the slot. Even a missed old profile cannot
  // read or write a replacement department with a new generation.
  assert.equal((await db('departments/dept1', 'owner', null)).status, 200);
  const nextGeneration = '02'.repeat(16);
  assert.equal((await db('departments/dept1', at, {...empty, name:'Biology', generation:nextGeneration}, create)).status, 200);
  assert.equal((await db('departments/dept1', pt)).status, 401);
  assert.equal((await db('departments/dept1/mode', pt, 'exam')).status, 401);
  const newProfile = { ...assignment, departmentGeneration:nextGeneration };
  assert.equal((await db(`users/${unassigned.localId}`, at, newProfile)).status, 200);
  assert.equal((await db('departments/dept1', ut)).status, 200);
  assert.equal((await db('departments/dept2', dt, marker)).status, 200);
  assert.deepEqual((await db('departments/icbs', 'owner')).value, legacy);
});
