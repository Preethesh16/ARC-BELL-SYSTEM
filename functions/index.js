const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getDatabase} = require('firebase-admin/database');
const {onRequest} = require('firebase-functions/v2/https');
const {createHandler} = require('./provisioning');

const emulatorProject = process.env.GCLOUD_PROJECT;
if (process.env.FUNCTIONS_EMULATOR === 'true' &&
    (!process.env.FIREBASE_AUTH_EMULATOR_HOST || !process.env.FIREBASE_DATABASE_EMULATOR_HOST)) {
  throw new Error('Local provisioning requires both Auth and Realtime Database emulators.');
}
initializeApp({
  databaseURL: process.env.FIREBASE_DATABASE_EMULATOR_HOST
    ? `https://${emulatorProject}-default-rtdb.firebaseio.com`
    : process.env.BELL_DATABASE_URL ?? undefined,
});
exports.departmentAdmin = onRequest({region: 'asia-southeast1', cors: true},
  (req, res) => createHandler(getAuth(), getDatabase())(req, res));
