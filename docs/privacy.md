---
layout: default
title: Privacy Policy
permalink: /privacy
---

<style>
  :root {
    --lectra-primary: #0A84FF;
    --lectra-secondary: #1C4E80;
    --lectra-ink: #0B1726;
    --lectra-muted: #4C5A6B;
    --lectra-bg: #F6F8FB;
    --lectra-card: #FFFFFF;
    --lectra-border: #E0E3E7;
  }

  .privacy-wrap {
    background: var(--lectra-bg);
    border-radius: 20px;
    padding: 32px;
    max-width: 920px;
    margin: 24px auto 48px;
    box-shadow: 0 16px 32px rgba(20, 24, 27, 0.08);
  }

  .privacy-hero {
    display: flex;
    gap: 16px;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    margin-bottom: 24px;
  }

  .privacy-title {
    font-size: 2.2rem;
    font-weight: 700;
    color: var(--lectra-ink);
    margin: 0 0 6px 0;
  }

  .privacy-subtitle {
    color: var(--lectra-muted);
    margin: 0;
    font-size: 1rem;
  }

  .pill {
    background: rgba(75, 57, 239, 0.12);
    color: var(--lectra-primary);
    padding: 6px 14px;
    border-radius: 999px;
    font-weight: 600;
    font-size: 0.85rem;
  }

  .privacy-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: 16px;
    margin: 24px 0;
  }

  .privacy-card {
    background: var(--lectra-card);
    border: 1px solid var(--lectra-border);
    border-radius: 16px;
    padding: 18px 20px;
  }

  .privacy-card h3 {
    margin-top: 0;
    color: var(--lectra-ink);
    font-size: 1.05rem;
  }

  .privacy-card p,
  .privacy-card li {
    color: var(--lectra-muted);
    line-height: 1.6;
  }

  .privacy-section {
    background: var(--lectra-card);
    border: 1px solid var(--lectra-border);
    border-radius: 16px;
    padding: 20px 24px;
    margin-bottom: 16px;
  }

  .privacy-section h2 {
    margin-top: 0;
    color: var(--lectra-ink);
  }

  .privacy-section p,
  .privacy-section li {
    color: var(--lectra-muted);
    line-height: 1.7;
  }

  .privacy-section ul {
    padding-left: 20px;
  }

  .privacy-footer {
    margin-top: 24px;
    color: var(--lectra-muted);
    font-size: 0.95rem;
  }

  a {
    color: var(--lectra-primary);
  }
</style>

<div class="privacy-wrap">
  <div class="privacy-hero">
    <div>
      <h1 class="privacy-title">Privacy Policy</h1>
      <p class="privacy-subtitle">Effective date: March 21, 2026</p>
    </div>
    <span class="pill">Lectra</span>
  </div>

  <div class="privacy-grid">
    <div class="privacy-card">
      <h3>At a glance</h3>
      <ul>
        <li>Audio recording and transcription run <strong>locally on your device</strong>.</li>
        <li>Recordings, transcripts, and notes stay <strong>on your device</strong> unless you share them.</li>
        <li>We only collect your <strong>email</strong> for login.</li>
        <li>No ads, no trackers, no selling data.</li>
      </ul>
    </div>
    <div class="privacy-card">
      <h3>Third‑party services</h3>
      <ul>
        <li>Supabase for authentication and a protected edge function that relays transcript text to Gemini.</li>
        <li>Google Gemini API for AI note structuring from transcript text.</li>
      </ul>
    </div>
    <div class="privacy-card">
      <h3>Your control</h3>
      <ul>
        <li>Delete recordings anytime from your device.</li>
        <li>Revoke microphone access in settings.</li>
        <li>Request account deletion anytime.</li>
      </ul>
    </div>
  </div>

  <div class="privacy-section">
    <h2>1. Information We Collect</h2>
    <ul>
      <li><strong>Email address</strong> (for account authentication via Supabase).</li>
      <li><strong>Audio recordings, transcripts, and notes</strong> are created and stored locally on your device.</li>
      <li><strong>Transcript text</strong> may be sent through a Supabase edge function to Gemini to generate structured notes. The Gemini API key is kept server-side.</li>
    </ul>
    <p>We do not upload your audio files to our servers.</p>
  </div>

  <div class="privacy-section">
    <h2>2. How We Use Information</h2>
    <ul>
      <li>Authenticate and manage your account.</li>
      <li>Provide core functionality (recording, local transcription, and notes).</li>
      <li>Send transcript text to Gemini to produce structured lecture notes.</li>
      <li>Maintain app stability and performance.</li>
    </ul>
  </div>

  <div class="privacy-section">
    <h2>3. Local Transcription</h2>
    <p>Lectra transcribes speech locally on your device using an on-device Whisper model. This means raw lecture audio remains on your device during transcription.</p>
    <p>A one-time model download may be required when using transcription for the first time.</p>
  </div>

  <div class="privacy-section">
    <h2>4. AI Note Structuring (Gemini)</h2>
    <p>After local transcription, Lectra can use Google Gemini (via Supabase edge function) to convert transcript text into organized notes (for example: Main Topics, Key Definitions, and Action Items).</p>
    <ul>
      <li>Only transcript text is sent for this step.</li>
      <li>Audio files are not uploaded by Lectra for note structuring.</li>
      <li>If AI note structuring is unavailable (offline/timeout), Lectra shows your raw transcript locally instead of empty note sections.</li>
    </ul>
  </div>

  <div class="privacy-section">
    <h2>5. Data Sharing</h2>
    <p>We do not sell your data. We only share limited information with:</p>
    <ul>
      <li><strong>Supabase</strong> for account authentication (email address only) and a secured edge function to relay transcripts.</li>
      <li><strong>Google Gemini API</strong> for transcript-to-notes processing.</li>
    </ul>
  </div>

  <div class="privacy-section">
    <h2>6. Permissions</h2>
    <ul>
      <li><strong>Microphone</strong> — required to record lectures.</li>
      <li><strong>Internet</strong> — required for authentication, first-time model download, and Gemini note structuring.</li>
      <li><strong>Android foreground/background behavior</strong> — used so recording can continue when screen is off or app is in background.</li>
    </ul>
  </div>

  <div class="privacy-section">
    <h2>7. Data Retention</h2>
    <ul>
      <li>Local recordings and notes remain on your device until you delete them or uninstall the app.</li>
      <li>Account data (email) is retained while your account remains active.</li>
      <li>Any transcript text sent to Gemini is processed under Google’s applicable service terms and retention policies.</li>
      <li>Exports (PDF/DOCX) are generated locally and saved/shared only when you choose to export.</li>
    </ul>
  </div>

  <div class="privacy-section">
    <h2>8. Security</h2>
    <p>We use industry‑standard safeguards for authentication data and secure connections. However, no system is 100% secure.</p>
  </div>

  <div class="privacy-section">
    <h2>9. Your Rights & Choices</h2>
    <ul>
      <li>Delete local recordings at any time.</li>
      <li>Revoke permissions via device settings.</li>
      <li>Request account deletion by contacting us.</li>
    </ul>
  </div>

  <div class="privacy-section">
    <h2>10. Children’s Privacy</h2>
    <p>Lectra is not intended for children under 13.</p>
  </div>

  <div class="privacy-section">
    <h2>11. Contact</h2>
    <p>Questions or deletion requests: <a href="mailto:goydave45@gmail.com">goydave45@gmail.com</a></p>
  </div>

  <div class="privacy-section">
    <h2>12. Current Release Notes (Privacy-Relevant)</h2>
    <ul>
      <li>Speech-to-text is performed locally using an on-device Whisper model.</li>
      <li>Recordings and saved note files are stored locally and remain until user deletion.</li>
      <li>Structured notes are generated from transcript text via a Supabase edge function that holds the Gemini API key; audio is not uploaded by Lectra for this step.</li>
      <li>If AI note structuring is unavailable, Lectra displays only the raw transcript locally.</li>
      <li>PDF/DOCX exports are produced on-device and shared only when initiated by the user.</li>
      <li>On Android, foreground recording support is used to keep recording active when the app is backgrounded or screen turns off.</li>
      <li>Sharing recordings to other apps happens only when a user explicitly taps Share.</li>
    </ul>
  </div>

  <p class="privacy-footer">We may update this policy from time to time. Changes will be posted on this page.</p>
</div>
