---
layout: default
title: Privacy Policy
permalink: /privacy
---

<style>
  :root {
    --lectra-primary: #4B39EF;
    --lectra-secondary: #39D2C0;
    --lectra-ink: #14181B;
    --lectra-muted: #57636C;
    --lectra-bg: #F1F4F8;
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
      <p class="privacy-subtitle">Effective date: February 10, 2026</p>
    </div>
    <span class="pill">Lectra</span>
  </div>

  <div class="privacy-grid">
    <div class="privacy-card">
      <h3>At a glance</h3>
      <ul>
        <li>Recordings and notes are stored <strong>locally</strong> on your device.</li>
        <li>We only collect your <strong>email</strong> for login.</li>
        <li>No ads, no trackers, no selling data.</li>
      </ul>
    </div>
    <div class="privacy-card">
      <h3>Third‑party services</h3>
      <ul>
        <li>Supabase for authentication.</li>
        <li>Device speech recognition for transcripts.</li>
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
    </ul>
    <p>We do not collect or upload your audio, transcripts, or notes to our servers.</p>
  </div>

  <div class="privacy-section">
    <h2>2. How We Use Information</h2>
    <ul>
      <li>Authenticate and manage your account.</li>
      <li>Provide core functionality (recording, transcription, and notes).</li>
      <li>Maintain app stability and performance.</li>
    </ul>
  </div>

  <div class="privacy-section">
    <h2>3. Speech Recognition</h2>
    <p>Lectra uses your device’s built‑in speech recognition services to create transcripts. Depending on your OS, audio may be processed by your device vendor (e.g., Google or Apple) to return transcribed text. We do not receive or store this audio on our servers.</p>
  </div>

  <div class="privacy-section">
    <h2>4. Data Sharing</h2>
    <p>We do not sell your data. We only share limited information with:</p>
    <ul>
      <li><strong>Supabase</strong> for account authentication (email address only).</li>
      <li><strong>Device speech services</strong> required for transcription on your device.</li>
    </ul>
  </div>

  <div class="privacy-section">
    <h2>5. Permissions</h2>
    <ul>
      <li><strong>Microphone</strong> — required to record lectures.</li>
      <li><strong>Speech recognition</strong> — required to generate transcripts.</li>
      <li><strong>Internet</strong> — required for authentication.</li>
    </ul>
  </div>

  <div class="privacy-section">
    <h2>6. Data Retention</h2>
    <ul>
      <li>Local recordings and notes remain on your device until you delete them or uninstall the app.</li>
      <li>Account data (email) is retained while your account remains active.</li>
    </ul>
  </div>

  <div class="privacy-section">
    <h2>7. Security</h2>
    <p>We use industry‑standard safeguards for authentication data and secure connections. However, no system is 100% secure.</p>
  </div>

  <div class="privacy-section">
    <h2>8. Your Rights & Choices</h2>
    <ul>
      <li>Delete local recordings at any time.</li>
      <li>Revoke permissions via device settings.</li>
      <li>Request account deletion by contacting us.</li>
    </ul>
  </div>

  <div class="privacy-section">
    <h2>9. Children’s Privacy</h2>
    <p>Lectra is not intended for children under 13.</p>
  </div>

  <div class="privacy-section">
    <h2>10. Contact</h2>
    <p>Questions or deletion requests: <a href="mailto:goydave45@gmail.com">goydave45@gmail.com</a></p>
  </div>

  <p class="privacy-footer">We may update this policy from time to time. Changes will be posted on this page.</p>
</div>
