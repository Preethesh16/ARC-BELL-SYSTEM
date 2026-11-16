const test = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getDatabase} = require('firebase-admin/database');
const {createHandler} = require('./provisioning');

const projectId = 'demo-college-bell';
const databaseHost = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!/^127\.0\.0\.1:\d+$/.test(databaseHost || '') ||
    !/^127\.0\.0\.1:\d+$/.test(authHost || '')) {
  throw new Error('Run only with the local Firebase emulators (see DEPARTMENT_SETUP.md).');
}
const app = initializeApp({
  projectId,
  databaseURL: `https://${projectId}-default-rtdb.firebaseio.com`,
});
const auth = getAuth(app);
const db = getDatabase(app);
test.after(() => deleteApp(app));
const functionUrl = process.env.BELL_TEST_FUNCTION_URL;
if (functionUrl && functionUrl !== 'http://127.0.0.1:5001/demo-college-bell/asia-southeast1/departmentAdmin') {
  throw new Error('The test function must be the local demo endpoint.');
}
const password = 'OnlyForSimulator2026!';
const legacy = {name: 'Mathematics', mode: 'college', schedules: {college: {times: [510]}}};

async function signIn(email, secret = password) {
  const result = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-key`, {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({email, password: secret, returnSecureToken: true}),
  });
  return {status: result.status, ...await result.json()};
}

async function readOrWrite(path, token, method = 'GET', body) {
  const url = new URL(`http://${databaseHost}/${path}.json`);
  url.searchParams.set('ns', `${projectId}-default-rtdb`);
  if (token) url.searchParams.set('auth', token);
  const res = await fetch(url, {method, body: body === undefined ? undefined : JSON.stringify(body)});
  return {status: res.status, data: await res.json()};
}

async function call(token, body, database = db) {
  if (functionUrl && database === db) {
    const headers = {'Content-Type': 'application/json'};
    if (token) headers.Authorization = `Bearer ${token}`;
    const response = await fetch(functionUrl, {method: 'POST', headers, body: JSON.stringify(body)});
    return {status: response.status, data: await response.json()};
  }
  const req = {
    method: 'POST',
    get: () => token ? `Bearer ${token}` : undefined,
    is: () => true,
    body,
  };
  const response = {set() {}, status(status) { this.code = status; return this; }, json(data) { return {status: this.code, data}; }};
  return createHandler(auth, database)(req, response);
}

test('provisioning and per-department access with simulated bell data', async () => {
  const identities = Object.fromEntries(await Promise.all(
    ['admin', 'superadmin', 'secretary'].map(async role => {
      const email = `${role}@example.test`;
      const {uid} = await auth.createUser({email, password});
      await db.ref(`users/${uid}`).set({role, departments: {icbs: true}});
      const login = await signIn(email);
      assert.equal(login.status, 200);
      return [role, {uid, token: login.idToken}];
    }),
  ));
  await db.ref('departments/icbs').set(legacy);
  const admin = identities.admin.token;
  const developer = identities.superadmin.token;
  const icbs = identities.secretary.token;

  assert.equal((await call(null, {action: 'createDepartment', name: 'Unauthorized'})).status, 401);
  assert.equal((await call('invalid', {action: 'createDepartment', name: 'Unauthorized'})).status, 401);
  assert.equal((await call(icbs, {action: 'createDepartment', name: 'Blocked'})).status, 403);
  const [a, b] = await Promise.all([
    call(admin, {action: 'createDepartment', name: 'Physics'}),
    call(developer, {action: 'createDepartment', name: 'Computing'}),
  ]);
  assert.equal(a.status, 201);
  assert.equal(b.status, 201);
  assert.deepEqual([a.data.id, b.data.id].sort(), ['dept1', 'dept2']);
  assert.equal((await call(developer, {action: 'renameDepartment', id: a.data.id, name: 'Applied Physics'})).status, 200);
  assert.equal((await call(admin, {action: 'renameDepartment', id: 'icbs', name: 'Blocked'})).status, 400);
  assert.equal((await readOrWrite('managedDepartments', admin)).status, 200);
  assert.equal((await readOrWrite('managedDepartments', developer)).status, 200);
  assert.equal((await readOrWrite('departments/icbs', icbs)).status, 200);
  assert.equal((await readOrWrite('departments', icbs)).status, 401);
  const icbsProfile = `users/${identities.secretary.uid}`;
  assert.equal((await readOrWrite(`${icbsProfile}/role`, icbs, 'PUT', 'superadmin')).status, 401);
  assert.equal((await readOrWrite(`${icbsProfile}/departments/${a.data.id}`, icbs, 'PUT', true)).status, 401);
  assert.equal((await readOrWrite(icbsProfile, icbs, 'PUT', {role: 'admin', departments: {icbs: true}})).status, 401);
  assert.equal((await readOrWrite(`managedDepartments/${a.data.id}`, icbs)).status, 401);

  const provision = {action: 'createSecretary', id: a.data.id, email: 'physics@example.test', password};
  assert.equal((await call(icbs, provision)).status, 403);
  const saved = await call(admin, provision);
  assert.equal(saved.status, 201);
  const data = await signIn(provision.email);
  assert.equal(data.status, 200);
  const me = await readOrWrite(`users/${saved.data.uid}`, data.idToken);
  assert.deepEqual(me, {status: 200, data: {role: 'secretary', departments: {[a.data.id]: true}, managedDepartment: a.data.id}});
  assert.equal((await call(developer, {...provision, id: b.data.id, email: 'computing@example.test'})).status, 201);
  assert.equal((await call(developer, {...provision, id: b.data.id, password: 'DifferentTestOnlyPassword!'})).status, 409);
  assert.equal((await signIn(provision.email)).status, 200);

  const mine = `managedDepartments/${a.data.id}`;
  const other = `managedDepartments/${b.data.id}`;
  const user = data.idToken;
  assert.equal((await readOrWrite(mine, user)).data.name, 'Applied Physics');
  assert.equal((await readOrWrite('managedDepartments', user)).status, 401);
  assert.equal((await readOrWrite(other, user)).status, 401);
  assert.equal((await readOrWrite('departments/icbs', user)).status, 401);
  assert.equal((await readOrWrite('departments/icbs/mode', user, 'PUT', 'exam')).status, 401);
  assert.equal((await readOrWrite(`users/${saved.data.uid}/role`, user, 'PUT', 'admin')).status, 401);
  assert.equal((await readOrWrite(`${mine}/name`, user, 'PUT', 'Blocked')).status, 401);
  assert.equal((await readOrWrite(`${mine}/name`, admin, 'PUT', 'Blocked')).status, 401);
  assert.equal((await readOrWrite(`${other}/mode`, user, 'PUT', 'exam')).status, 401);
  assert.equal((await readOrWrite(`${mine}/mode`, user, 'PUT', 'exam')).status, 200);
  assert.equal((await readOrWrite(`${mine}/schedules/exam/times`, user, 'PUT', [515])).status, 200);
  assert.ok((await readOrWrite(`${mine}/schedules/exam/times`, user, 'PUT', [1440])).status >= 400);
  assert.equal((await readOrWrite(`${mine}/manualRing`, user)).data, null);

  const failEmail = 'failed-profile@example.test';
  const failProfile = {
    ref(path) {
      const ref = db.ref(path);
      return /^users\/[^/]+$/.test(path)
        ? {set: async () => { throw new Error('Injected write failure'); }, remove: () => ref.remove()}
        : ref;
    },
  };
  assert.equal((await call(admin, {...provision, email: failEmail}, failProfile)).status, 500);
  await assert.rejects(auth.getUserByEmail(failEmail), {code: 'auth/user-not-found'});
  assert.equal((await signIn(failEmail)).status, 400);
  assert.deepEqual((await db.ref('departments/icbs').get()).val(), legacy);
});
