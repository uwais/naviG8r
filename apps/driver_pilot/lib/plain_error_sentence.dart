import "package:dio/dio.dart" show DioException;

import "pilot_api.dart";

/// formatApiError's own sentences, but never its "HTTP n" or server-address fallbacks
/// (decisions.md 7): those become [fallback], as does anything that is not a server answer.
String plainErrorSentence(Object error, String fallback) {
  if (error is! DioException || serverNeverAnswered(error)) return fallback;
  final sentence = formatApiError(error);
  return sentence.startsWith("HTTP ") || sentence.startsWith("Cannot reach")
      ? fallback
      : sentence;
}
