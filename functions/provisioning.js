const {randomUUID} = require('node:crypto');

class RequestError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const departmentId = /^dept[1-9][0-9]{0,11}$/;
const admins = new Set(['admin', 'superadmin']);

async function adminIdentity(auth, db, header) {
  const token = /^Bearer ([^\s]+)$/.exec(header || '')?.[1];
  if (!token) throw new RequestError(401, 'Sign in again to continue.');
  let uid;
  try {
    ({uid} = await auth.verifyIdToken(token, true));
  } catch {
    throw new RequestError(401, 'Sign in again to continue.');
  }
  const role = (await db.ref(`users/${uid}/role`).get()).val();
  if (!admins.has(role)) throw new RequestError(403, 'Administrator access is required.');
}

function displayName(value) {
  const name = typeof value === 'string' ? value.trim() : '';
  if (!name || name.length > 80) throw new RequestError(400, 'Enter a department name of up to 80 characters.');
  return name;
}

async function createDepartment(db, name) {
  const legacy = (await db.ref('departments').get()).val() || {};
  const ref = db.ref('managedDepartments');
  const creationId = randomUUID();
  // Allocation and creation share one transaction; retry on concurrent changes.
  const result = await ref.transaction(existing => {
    const departments = existing || {};
    const highest = Math.max(0, ...[...Object.keys(legacy), ...Object.keys(departments)]
      .filter(id => departmentId.test(id)).map(id => Number(id.slice(4))));
    const id = `dept${highest + 1}`;
    if (!departmentId.test(id)) return;
    // The marker identifies our record when Firebase retries the transaction.
    return {...departments, [id]: {name, mode: 'college', config: {ringDurationSec: 5, timezone: 'IST'}, creationId}};
  });
  if (!result.committed) throw new RequestError(409, 'No department ID was available.');
  const id = Object.keys(result.snapshot.val()).find(key => result.snapshot.child(key).child('creationId').val() === creationId);
  return {id, name};
}

async function createSecretary(auth, db, id, input) {
  const email = typeof input.email === 'string' ? input.email.trim().toLowerCase() : '';
  const password = input.password;
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new RequestError(400, 'Enter a valid email address.');
  }
  if (typeof password !== 'string' || password.length < 12 || password.length > 128) {
    throw new RequestError(400, 'Use an initial password between 12 and 128 characters.');
  }
  let user;
  try {
    user = await auth.createUser({email, password, disabled: true});
  } catch (error) {
    if (error.code === 'auth/email-already-exists') throw new RequestError(409, 'An account with this email already exists.');
    if (error.code === 'auth/invalid-password' || error.code === 'auth/invalid-email') {
      throw new RequestError(400, 'Firebase rejected the email or password.');
    }
    throw error;
  }
  const profile = db.ref(`users/${user.uid}`);
  try {
    await profile.set({role: 'secretary', departments: {[id]: true}, managedDepartment: id});
    await auth.updateUser(user.uid, {disabled: false});
  } catch {
    // Only touch the newly created UID. Either successful cleanup blocks access.
    const rollback = await Promise.allSettled([auth.deleteUser(user.uid), profile.remove()]);
    if (rollback.some(item => item.status === 'rejected')) {
      console.error('Secretary provisioning rollback needs review', {uid: user.uid});
    }
    throw new RequestError(500, 'Could not finish creating the login. Ask the administrator to review it before retrying.');
  }
  return {uid: user.uid};
}

function createHandler(auth, db) {
  return async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      if (req.method !== 'POST') throw new RequestError(405, 'Use POST.');
      await adminIdentity(auth, db, req.get('authorization'));
      if (!req.is('application/json') || (req.rawBody?.length ?? 0) > 8192 || !req.body || Array.isArray(req.body) || typeof req.body !== 'object') {
        throw new RequestError(400, 'Expected a small JSON request.');
      }
      const input = req.body;
      if (input.action === 'createDepartment') {
        return res.status(201).json(await createDepartment(db, displayName(input.name)));
      }
      if (!['renameDepartment', 'createSecretary'].includes(input.action) || typeof input.id !== 'string' || !departmentId.test(input.id)) {
        throw new RequestError(400, 'Select a department created in Manage Departments.');
      }
      const ref = db.ref(`managedDepartments/${input.id}`);
      if (!(await ref.get()).exists()) throw new RequestError(404, 'Department not found.');
      if (input.action === 'renameDepartment') {
        const name = displayName(input.name);
        await ref.child('name').set(name);
        return res.status(200).json({id: input.id, name});
      }
      return res.status(201).json(await createSecretary(auth, db, input.id, input));
    } catch (error) {
      if (error instanceof RequestError) return res.status(error.status).json({error: error.message});
      console.error('Department management failed');
      return res.status(500).json({error: 'Department management is temporarily unavailable.'});
    }
  };
}

module.exports = {createHandler};
