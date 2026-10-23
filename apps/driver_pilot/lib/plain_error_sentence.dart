import "package:dio/dio.dart" show DioException;

import "pilot_api.dart";

/// What a screen says when a request fails: formatApiError's own sentences, but never its "HTTP n",
/// raw-error or server-address fallbacks (decisions.md 7). Those become [fallback], as does anything that
/// is not a server answer. Without a [fallback], the app's general sentences stand in.
String plainErrorSentence(Object error, [String? fallback]) {
  if (serverNeverAnswered(error)) {
    return fallback ??
        "Could not reach NaviG8r. Check your connection and try again.";
  }
  const somethingWentWrong = "Something went wrong. Please try again.";
  if (error is! DioException) return fallback ?? somethingWentWrong;
  final sentence = formatApiError(error);
  return sentence.startsWith("HTTP ") || sentence.startsWith("Cannot reach")
      ? fallback ?? somethingWentWrong
      : sentence;
}
