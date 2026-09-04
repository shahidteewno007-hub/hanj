# Firestore rules tests

Emulator tests for `../firestore.rules`. Test-only — nothing here ships with the app,
and these dependencies are deliberately kept out of the Flutter project.

```bash
cd firestore-tests
npm install
npm test          # starts the Firestore emulator, runs the tests, shuts it down
```

## Java

The emulator needs a JRE, and `firebase-tools` v14+ requires **Java 21 or newer**.

The project's build JDK is 17 (`C:\Users\ABC\Dev\jdk17`) and **must stay 17** — Gradle
depends on it. Do not change `JAVA_HOME` for this.

Android Studio ships a JetBrains Runtime at 21, which is what these tests use. Put it on
`PATH` for the test run only:

```bash
export PATH="/c/Program Files/Android/Android Studio/jbr/bin:$PATH"
npm test
```

`firebase-tools` is installed locally rather than used from the global `firebase.cmd`.
The global CLI is a bundled-Node build whose first-run wizard crashes intermittently
(`SyntaxError: Unexpected end of JSON input` in `firepit/welcome.js`), which made test
runs unreliable. The local install runs under the system Node and is reproducible.

## What the tests assert

Each rule change proves **both halves**: the access that should still work, and the access
that should now be denied. Where a test asserts something undesirable but currently
accepted — the cross-user read in `users-read.test.js` — it says so, and names what is
still exposed, so the cost is visible in the test output rather than only in a report.
