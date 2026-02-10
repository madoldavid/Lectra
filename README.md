# Lectra

Lectra is a Flutter mobile app for recording live lectures and turning them into structured notes. It captures audio, transcribes in real time, and saves both the recording and notes locally for quick access.

## Overview
Lectra is built for speed and focus. The Home screen centers on one‑tap recording, while the Library lists only recordings created on the device. The app is designed to be lightweight, offline‑friendly for capture/transcription, and ready to scale into cloud processing later.

## Key Features
- Email/password authentication with Supabase
- One‑tap lecture recording with live transcription
- Local storage of audio, transcript, and structured notes
- Recent Lectures list shows only real recordings
- Library view for browsing recorded lectures

## Tech Stack
- Flutter + Dart
- Supabase Auth (email/password)
- `record` for audio capture
- `speech_to_text` for on‑device transcription
- Local file storage via `path_provider`

## How It Works
1. User taps the mic button on Home.
2. Audio is recorded to local storage.
3. Live transcription is captured on device.
4. A notes file and metadata file are saved next to the audio.
5. Home and Library read only these saved recordings.

## Local Storage Format
Recorded files are stored under the app’s documents directory in `recordings/`:
- Audio: `lecture_<timestamp>.m4a`
- Notes: `lecture_<timestamp>.txt`
- Metadata: `lecture_<timestamp>.json`

## Permissions
- Android: `RECORD_AUDIO`, `INTERNET`
- iOS: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`

## Configuration
Supabase configuration is currently set in:
- `lib/backend/supabase/supabase.dart`

For production, consider replacing hardcoded values with `--dart-define` and environment‑specific configuration.

## Run Locally
1. Install Flutter (stable channel).
2. Install Android Studio and SDK tools.
3. Run:
   
   ```bash
   flutter pub get
   flutter run -d emulator-5554
   ```

## Build Artifacts
Debug APK:
```bash
flutter build apk --debug
```

Release AAB:
```bash
flutter build appbundle --release
```

Output:
- `build/app/outputs/bundle/release/app-release.aab`

## Android Signing (Release)
- Keystore path: `android/lectra-keystore.jks`
- Signing config: `android/key.properties`

Make sure the keystore is backed up securely. Losing it prevents future Play Store updates.

## Project Structure
- `lib/pages/home/` — Home screen and recording entry point
- `lib/notes_page/` — Library view
- `lib/backend/recordings/` — Local recording metadata storage
- `lib/auth/` — Supabase authentication flow
- `android/` — Android build and signing config

## Troubleshooting
- Run `flutter doctor -v` to verify SDKs and licenses.
- If the emulator is not detected, start it in Android Studio’s Device Manager.
- If speech recognition fails, confirm microphone permissions on the device.

## Status
MVP is production‑ready for Android release with email/password auth, local recording, and transcription. Cloud transcription and structured AI summaries can be added in the next phase.
