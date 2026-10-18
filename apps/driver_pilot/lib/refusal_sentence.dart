import "pilot_api.dart";

/// What a carrier or driver screen says when a request fails: the server's sentence or the app's own, never
/// formatApiError's fallbacks, which print "HTTP 400: {…}", the raw error, or the API address with build flags.
String refusalSentence(Object error) {
  if (serverNeverAnswered(error)) {
    return "Could not reach NaviG8r. Check your connection and try again.";
  }
  final sentence = formatApiError(error);
  if (sentence == error.toString() || sentence.startsWith("HTTP ")) {
    return "Something went wrong. Please try again.";
  }
  return sentence;
}
