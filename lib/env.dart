// Supabase edge function that structures notes (keeps Gemini key server-side).
const notesProxyUrl =
    'https://kjakcnlchljralfsqagx.supabase.co/functions/v1/structure-notes';

// Keep client-side Gemini key empty for production.
const geminiApiKey = '';
