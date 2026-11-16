'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const project = process.env.BELL_PROJECT_ID;
const databaseUrl = process.env.BELL_DATABASE_URL;
const [id, ...flags] = process.argv.slice(2);
const apply = flags.includes('--apply');
const release = flags.includes('--release-after-esp-retired');
const expected = flags.find(f => f.startsWith('--expect-email='))?.slice(15);
async function main() {
  if (!/^dept[1-9][0-9]{0,11}$/.test(id || '') || !process.env.BELL_CLI_LIB || !project || !databaseUrl ||
      flags.some(f => !['--apply','--release-after-esp-retired'].includes(f) && !f.startsWith('--expect-email='))) {
    throw Error('Set BELL_CLI_LIB, BELL_PROJECT_ID, and BELL_DATABASE_URL. Usage: node scripts/retire-department.cjs dept1 [--apply] [--release-after-esp-retired] [--expect-email=address]');
  }
  const load = name => require(path.join(process.env.BELL_CLI_LIB, name));
  const auth = load('auth');
  const options = {project};
  const operator = auth.getGlobalDefaultAccount();
  if (!operator) throw Error('Sign in to the Firebase CLI as a project operator first.');
  auth.setActiveAccount(options, operator);
  await load('requireAuth').requireAuth(options);
  const {Client} = load('apiv2');
  const db = new Client({urlPrefix:new URL(databaseUrl).origin});
  const api = new Client({urlPrefix:'https://identitytoolkit.googleapis.com',apiVersion:'v1'});
  const route = '/departments/' + id + '.json';
  const users = async () => Object.entries((await db.get('/users.json')).body || {}).filter(([, p]) =>
    p?.managedDepartment === id || p?.departments?.[id] === true);
  const lookup = async uid => (await api.post('/projects/'+project+'/accounts:lookup',{localId:[uid]})).body.users?.[0];
  const read = loc => db.get(loc,{headers:{'X-Firebase-ETag':'true'}});
  function write(loc, value, current) {
    const tag = current.response.headers.get('etag');
    assert.ok(tag, 'Missing Firebase ETag');
    return db.put(loc,value,{headers:{'If-Match':tag}});
  }
  const reserved = value => value?.deleted === true && Object.keys(value).length === 1;
  const before = await read(route);
  if (before.body !== null && !reserved(before.body)) throw Error('Refusing to touch a live department or unrecognized record.');
  const matches = await users();
  for (const [uid, p] of matches) {
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(uid) || p.role !== 'secretary' || p.managedDepartment !== id ||
        Object.keys(p.departments || {}).length !== 1 || p.departments[id] !== true) {
      throw Error('Found a shared or unexpected account; review manually.');
    }
    const account = await lookup(uid);
    if (account && (account.localId !== uid || (expected && account.email !== expected))) throw Error('Unexpected secretary account.');
  }
  console.log(id + ': ' + matches.length + ' exclusive secretary profile(s). ' + (apply ? 'Applying cleanup.' : 'Dry run.'));
  if (!apply) return;
  if (before.body === null) await write(route,{deleted:true},before);
  const marker = await read(route);
  assert.ok(reserved(marker.body),'Department slot changed');
  for (const [uid, p] of matches) {
    const profilePath = '/users/'+uid+'.json';
    const current = await read(profilePath);
    assert.deepEqual(current.body,p,'Profile changed');
    if (await lookup(uid)) await api.post('/projects/'+project+'/accounts:delete',{localId:uid});
    assert.ok(!(await lookup(uid)), 'Auth account still exists');
    await write(profilePath,null,current);
  }
  assert.equal((await users()).length,0,'Old profile bindings remain');
  if (release) {
    await write(route,null,marker);
    assert.equal((await read(route)).body,null,'ID release could not be verified');
  }
  console.log(release ? 'Secretary cleanup verified; ID released.' : 'Secretary cleanup verified; ID reserved until ESP retirement is confirmed.');
}
main().catch(error => {console.error(error.message);process.exitCode=1;});
