
import 'dart:async';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  final String apiKey;

  GeminiService(this.apiKey);

  Future<String> generateNotes(String transcript) async {
    try {
      final model = GenerativeModel(model: 'gemini-pro', apiKey: apiKey);
      final content = [Content.text('Summarize the following transcript in the style of detailed, well-structured meeting notes. Use headings, bullet points, and bold text to organize the information. The summary should be comprehensive and capture all key decisions, action items, and important topics discussed. Transcript: $transcript')];
      final response = await model.generateContent(content);
      return response.text ?? 'No response from Gemini.';
    } catch (e) {
      return 'An exception occurred while trying to generate notes: $e';
    }
  }
}
