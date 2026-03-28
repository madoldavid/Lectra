# Lectra — Inside‑Out System Design & Architecture (Interview‑Ready)

_Last updated: 2026‑03‑13 (Asia/Dubai)_

## 1) Executive Summary
Lectra is a **local‑first lecture recorder and note‑structuring app**. It records long lectures, transcribes them on‑device using Whisper, and then sends only the transcript to Gemini to produce **clean, structured study notes**. All recordings, transcripts, and notes are stored locally and persist until the user deletes them. Authentication, notifications, and profile settings are handled through Supabase.

## 2) Product Goals & Non‑Goals
**Goals**
- Record long lectures reliably (60+ minutes).
- Produce **structured, readable notes** with strong headings and summaries.
- Keep audio and transcripts **on‑device** for privacy.
- Make the app resilient to backgrounding, locks, and emulator limitations.

**Non‑Goals (current scope)**
- Full server‑side audio processing pipeline.
- Advanced collaboration/multi‑user note sync.
- Guaranteed perfect notes with every ASR/AI edge case (we implement robust fallback and repair instead).

## 3) High‑Level Architecture
**Tech Stack**
- Flutter (UI + platform integration)
- Supabase (Auth, notifications, user management)
- Whisper (on‑device transcription via `whisper_ggml`)
- Gemini (cloud LLM for note structuring)
- Local file storage (recordings + metadata)

**Mermaid overview**
```mermaid
flowchart TD
  A[User taps Record] --> B[Record Service: WAV 16kHz mono]
  B --> C[Local Storage: /recordings/*.wav]
  C --> D[Whisper Transcription (on-device)]
  D --> E[Transcript text]
  E --> F[Gemini Notes Service]
  F --> G[Structured Notes]
  G --> H[Local Storage: /recordings/*.txt + *.json]
  H --> I[Notes Detail UI]

  J[Supabase Auth] --> UI[Flutter UI]
  K[Supabase Realtime Notifications] --> L[Notification Sync Service]
  L --> UI
```

## 4) Core Runtime Flow (Recording → Notes)
**Step-by-step**
1. **Start recording**
   - Uses `record` package with WAV encoder, 16kHz, mono for Whisper.
   - Android uses **foreground service** so recording persists when screen locks.

2. **Stop recording**
   - File is finalized and stabilized on disk.
   - Whisper runs locally to generate a raw transcript.

3. **Notes structuring**
   - Transcript is sent to Gemini **(text only, not audio)**.
   - Gemini returns structured Markdown notes with fixed headings.
   - If Gemini output is weak, a repair pass runs.
   - If still weak, app falls back to local structured notes.

4. **Persistence**
   - Audio, notes, and metadata saved locally in the app documents directory.

5. **Display**
   - Notes shown in Notes Detail screen with section styling.

## 5) Core Components (Code Map)
### 5.1 UI Layer
- Entry: `lib/main.dart`
- Home: `lib/pages/home/home_widget.dart`
- Notes detail: `lib/notes_detail_page/notes_detail_page_widget.dart`
- Settings: `lib/pages/setting_page/setting_page_widget.dart`

### 5.2 Recording Service
- `lib/services/local_pcm_recording_service.dart`
- Uses WAV encoder (`AudioEncoder.wav`, 16kHz, mono). This is essential for Whisper accuracy.
- Android `AudioRecordingService` configured as foreground service.

### 5.3 Transcription (Whisper)
- `lib/services/whisper_transcription_service.dart`
- Whisper model is downloaded on‑demand and cached.
- Supports segmentation for long audio and fallback models if needed.
- Local transcription is **device‑only** for privacy.

### 5.4 Note Structuring (Gemini)
- `lib/services/gemini_service.dart`
- Uses Gemini models with fallback order for resilience.
- Prompts enforce headings:
  - `Lecture Summary`
  - `Main Topics`
  - `Key Definitions`
  - `Action Items`
  - `Additional Context (Beyond Recording)`
- Includes **repair pass** if output is not well‑formed.
- Validates output quality; otherwise local fallback notes are generated.

### 5.5 Storage Layer
- `lib/backend/recordings/recording_store.dart`
- Files stored at:
  - `/recordings/*.wav` (audio)
  - `/recordings/*.txt` (notes)
  - `/recordings/*.json` (metadata)
  - `/recordings/trash/` (deleted items)

### 5.6 Supabase Backend
- `lib/backend/supabase/supabase.dart`
- PKCE auth flow, local session storage with resilient fallback.
- Email/password auth is primary right now.

### 5.7 Notifications
- `lib/services/notification_sync_service.dart`
- Reads from Supabase `notifications` table.
- Uses realtime channel + 30s polling.
- Local cache in SharedPreferences for offline display.

## 6) Data Model (RecordingEntry)
Stored in JSON file per recording.
Fields:
- `id`
- `title`
- `createdAt`
- `durationSeconds`
- `audioPath`
- `notesPath`
- `transcriptPreview`
- `deletedAt`

## 7) Notes Intelligence: Robustness Strategy
**Why it’s reliable**
- Gemini output **must** include core headings.
- If output is partial/weak, automatic repair prompt runs.
- If still weak, local fallback structured notes are generated.
- Final pass ensures each section has content, even if minimal.

**Additional Context (Beyond Recording)**
- This section is intentionally labeled as supplemental.
- Gemini is instructed to provide only safe, high‑confidence context.
- If AI doesn’t provide it, app inserts a safe placeholder.

## 8) Permissions & Background Recording
**Android**
- `RECORD_AUDIO`
- `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MICROPHONE`
- `WAKE_LOCK`
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`

**Battery Optimization Handling**
- App prompts to allow background recording.
- `BatteryOptimizationService` provides shortcuts into Android settings.

## 9) Security & Privacy
- **Audio and transcripts are stored locally only.**
- Gemini only receives transcript text, not audio.
- Supabase handles auth; no PII leaves the device beyond auth/notifications.

**Important production note:**
- Gemini API key is embedded in app (`lib/env.dart`). This is acceptable for prototype/testing but should be moved to a backend proxy for production security.

## 10) Reliability & Fault Tolerance
- SharedPreferences fail‑safe storage for Supabase sessions.
- Fallback transcription models if main model fails.
- Fallback notes if Gemini fails.
- Repair pass for malformed AI output.
- Automatic recovery of recordings if metadata missing.

## 11) Testing & Verification
- `flutter analyze`
- `flutter test`
- `integration_test/whisper_smoke_test.dart`

## 12) Release & Build
- AAB build command example:
  ```bash
  flutter build appbundle --release --build-name=1.0.4 --build-number=16
  ```
- Package ID: `com.goydave.lectra`
- Keystore: `lectra-keystore.jks`

## 13) Interview‑Friendly Talking Points
**Why Flutter?**
- Fast iteration, single codebase, strong UI control, easy Android + iOS.

**Why Supabase?**
- Managed auth, realtime features, minimal backend effort.

**Why Whisper local?**
- Privacy, offline capability, avoids costly server audio processing.

**Why Gemini for notes?**
- Strong language structuring, can clean up transcript noise, supports long‑form summarization.

**How is reliability handled?**
- Multiple fallback layers: transcription fallbacks, Gemini retries, repair prompts, local fallback notes.

## 14) Known Limitations (Honest & Realistic)
- Long recordings consume storage and can stress low‑end devices.
- AI output quality depends on transcript quality.
- Gemini API key still client‑side in this build (should be server‑side for production).

## 15) Future Improvements (Roadmap‑style)
- Server‑side note structuring with rate limiting and key protection.
- Better diarization (distinguish lecturer vs students).
- Advanced search indexing.
- Cloud sync of recordings/notes (optional).

---

If you want, I can also generate a short “interview answers” appendix with sample responses to common questions.

## 16) Interview Q&A Appendix (Practical Answers)

### 1. What problem does Lectra solve?
Lectra helps students capture live lectures, turn them into structured notes, and keep everything locally for privacy. It removes the friction of manual note‑taking while still letting users review and refine their notes later.

### 2. Why Flutter for this app?
Flutter gives me one codebase for Android/iOS with full control over UI. It’s fast to iterate, and it’s stable for media‑heavy flows like audio recording and rich notes UI.

### 3. Why on‑device transcription instead of cloud?
Privacy and cost. Audio never leaves the phone, which matters for sensitive classroom content. It also avoids the cost and complexity of streaming audio to servers.

### 4. Why use Gemini at all if transcription is local?
Whisper gives raw transcript text. Gemini is best‑in‑class at **structuring, summarizing, and cleaning** noisy transcripts into readable notes. The transcript (not audio) is sent to Gemini, keeping the privacy boundary intact.

### 5. How do you handle long lectures (60+ minutes)?
Recordings are stored locally in WAV format and the transcription service supports segmentation to avoid memory spikes. Notes generation is chunked when transcripts are large, and merged afterward.

### 6. How do you keep recording running when the phone locks?
On Android we run recording inside a foreground service, plus prompt the user to allow battery‑optimization exceptions. That prevents the OS from killing the recorder during long sessions.

### 7. What happens if Gemini returns garbage output?
There’s a **repair pipeline**:
- Validate headings and content quality.
- If weak, re‑prompt with a repair instruction.
- If still weak, fall back to a structured local notes template built from transcript.

### 8. How do you guarantee note sections are populated?
A deterministic finalization pass enforces required sections and fills missing sections using transcript‑derived summaries, topic extraction, and safe fallback text. That ensures each note has a complete structure.

### 9. How are recordings stored and managed?
Each recording has:
- WAV audio file
- Notes text file
- JSON metadata file
They live in a local `recordings/` directory, and deletions are moved to `recordings/trash/` for recovery.

### 10. How do you handle search?
We index titles and transcript previews in local metadata. Search uses a simple normalized filter that is fast and reliable on device.

### 11. How does Supabase fit in?
Supabase provides authentication and realtime notifications. The core recording/transcription/note flow is fully local and does not depend on the backend.

### 12. How secure is the Gemini API key?
Right now the key is embedded for simplicity. In production I would move Gemini calls to a backend proxy with rate limiting and key protection.

### 13. What testing do you run?
- `flutter analyze` and `flutter test`
- Whisper integration smoke test
- Manual QA on device for background recording and real mic capture

### 14. What’s the biggest technical risk?
The biggest risk is audio capture reliability under different OEM power policies. That’s why we use foreground services and battery optimization prompts.

### 15. How would you scale this app to millions of users?
- Keep transcription local to avoid expensive cloud audio workloads.
- Move Gemini calls to a secure backend proxy to control cost.
- Introduce optional cloud sync for notes only (not audio).

### 16. Why the “Additional Context” section?
It helps users deepen understanding beyond the raw lecture, while being clearly labeled as supplemental. It’s optional and uses safe, general knowledge only.

### 17. What’s your proudest technical decision?
The layered reliability pipeline: local‑first transcription, intelligent LLM structuring, and deterministic fallbacks. It keeps the app stable even when AI output is imperfect.

### 18. What would you improve next?
- Better diarization (distinguish lecturer vs students)
- Stronger offline search index
- Cloud backup of notes only
- Enhanced visualization (timeline + highlights in audio)

## 17) Long‑Lecture Deep Dive (60–120 minutes+)
This section expands on how Lectra stays reliable for very long sessions.

### Capture & Resilience
- **Foreground microphone service** on Android with `WAKE_LOCK` + battery‑optimization opt‑out keeps recording alive when the screen sleeps or the user switches apps.
- **Checkpointing**: audio is flushed in rolling segments (e.g., 2–5 minutes) so progress is never lost; if the app dies, only the last open segment is at risk.
- **Screen‑off continuity**: recording keeps running when the display times out; stop is the only action that ends capture.

### Audio Format & Quality
- **16 kHz, mono, linear PCM (WAV)** chosen for Whisper compatibility and lower size than 44.1 kHz while preserving lecture intelligibility.
- **Input gain & noise**: we apply conservative AGC/noise reduction defaults to avoid clipping and reduce room hum; Gemini prompt later de‑emphasizes background chatter.

### Transcription (Whisper) at Scale
- **Segmentation**: long recordings are split into fixed windows (e.g., 2–3 minutes) before feeding Whisper to avoid RAM spikes.
- **Model caching**: the Whisper model is loaded once and reused per segment to avoid repeated warm‑up time.
- **Timestamps**: interim transcripts keep timestamps per segment so recovery/repair is possible after crashes.

### Notes Structuring (Gemini) for Long Text
- **Chunked prompting**: transcripts longer than model token limits are summarized per segment; a running outline is updated, then a final consolidation pass builds the full notes.
- **Repair & fallback**: if Gemini rate‑limits or returns weak output, the local fallback notes generator uses the stitched transcript.
- **Noise filtering**: prompts explicitly bias toward the lecturer’s voice and de‑prioritize side conversations; summary focuses on main concepts, definitions, and action items.

### Storage, Size, and Cleanup
- **Rolling file sizes**: 60–90 minutes at 16 kHz mono PCM ≈ ~550–850 MB; after Whisper completes, optional WAV compression (to AAC) can reclaim space if enabled.
- **Auto‑prune**: temporary chunk files are deleted once their transcript is persisted; final assets kept are WAV + notes + metadata.
- **Trash bin**: deletions move to `recordings/trash/` so long lectures can be restored.

### UX for Long Sessions
- **Waveform/animation while recording** to assure users capture is live.
- **Progress signals**: “Transcribing…”, “Structuring notes…” states with retry messaging for failures.
- **Backpressure messaging**: if storage or battery is low, the app warns early before starting long capture.

### Edge Cases & Mitigations
- **Low battery / aggressive OEM policies**: foreground service + optimization bypass prompt; if the OS still kills the app, last flushed chunks remain recoverable.
- **No network during structuring**: raw transcript is stored; Gemini structuring can be retried later when online.
- **Very long >120 min**: same segmentation pipeline; if token budget is exceeded, the app keeps a hierarchical outline (per‑segment summaries → master summary) to fit within limits.

### What to mention in an interview
- Local‑first pipeline for privacy and cost, with Gemini only seeing text, not audio.
- Chunked ingestion and hierarchical summarization to respect both compute and token limits.
- Foreground service + checkpointing makes 60–120 minute sessions survivable under lockscreen and multitasking.
