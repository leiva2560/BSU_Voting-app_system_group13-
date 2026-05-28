# Folder 7 — Full Application
**Member:** [Name]

## Screens Included
- Login, Registration
- User Dashboard (sidebar, welcome card, election cards)
- Election Detail, Candidate Detail, Vote Screen, Results Screen
- Admin Panel (sidebar with Elections, Candidates, Admins, Reports, Users tabs)

## Firebase Setup
- Firebase Auth, Firestore, App Check, Storage

## Admin Features
- Create/Edit/Delete elections
- Add/Edit/Delete candidates (photo stored as base64 in Firestore)
- Create admin accounts
- Reports with bar charts and PDF print
- View/Edit/Delete all users

## How to Run
`flutter pub get && flutter run`

## Firebase Console Steps
1. Enable Email/Password auth
2. Set Firestore rules (allow read: if true on users for login lookup)
3. Set Storage rules (allow write: if request.auth != null)
4. Register App Check debug token from logcat
