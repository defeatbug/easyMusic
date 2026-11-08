import 'package:flutter/foundation.dart';

/// The sign-in surface of the plugin host protocol (see the desktop
/// host's internal/plugin/host.go and the NetEase plugin's login()):
///
/// - `host.signInPrompt({qr, text})` is fire-and-forget: while a plugin
///   signs in (QR flow) it keeps updating what the app should show — a
///   QR payload to render plus a status line. There is no form variant
///   in the protocol and nothing is answered back.
/// - `host.webSignIn({url, cookiesOf, until, userAgent})` is async: the
///   app shows a web page, watches the cookies of [WebSignInRequest.cookiesOf],
///   and once every cookie named in [WebSignInRequest.until] exists it
///   answers `{cookie}` — the Cookie header for that address. Closing
///   the page early is giving up (an error).

/// What a plugin asks to be shown while it signs in.
class SignInPromptData {
  const SignInPromptData({this.qr = '', this.text = ''});

  /// Payload to render as a QR code (a URL the service's app scans).
  final String qr;

  /// Status line: what to do, or how it is going.
  final String text;

  factory SignInPromptData.fromJson(Map<String, dynamic> j) =>
      SignInPromptData(
        qr: j['qr']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
      );
}

/// A plugin's request for a web sign-in page.
class WebSignInRequest {
  const WebSignInRequest({
    required this.url,
    required this.cookiesOf,
    required this.until,
    this.userAgent = '',
  });

  /// The page to sign in on.
  final String url;

  /// The address whose cookies are the answer.
  final String cookiesOf;

  /// Cookie names that say the listener signed in.
  final List<String> until;

  /// User-Agent to present to the page ('' = the web view's own).
  final String userAgent;

  factory WebSignInRequest.fromJson(Map<String, dynamic> j) =>
      WebSignInRequest(
        url: j['url']?.toString() ?? '',
        cookiesOf: j['cookiesOf']?.toString() ?? '',
        until: (j['until'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        userAgent: j['userAgent']?.toString() ?? '',
      );
}

/// One cookie of a web view's store, reduced to what a Cookie header
/// needs.
class CookiePair {
  const CookiePair(this.name, this.value);
  final String name;
  final String value;
}

/// The Cookie header for [cookies], once every name in [until] is
/// present — the desktop host's cookieHeader rule: empty-valued cookies
/// are skipped, and a missing awaited name means "not signed in yet"
/// (null). With an empty [until] any non-empty cookie set completes.
String? buildCookieHeader(List<CookiePair> cookies, List<String> until) {
  final have = <String>{};
  final parts = <String>[];
  for (final c in cookies) {
    if (c.value.isEmpty) continue;
    have.add(c.name);
    parts.add('${c.name}=${c.value}');
  }
  for (final name in until) {
    if (!have.contains(name)) return null;
  }
  return parts.isEmpty ? null : parts.join('; ');
}

/// Splits a Cookie header ("a=1; b=2") back into pairs — the shape the
/// platform cookie store answers in. Values keep everything after the
/// first '=' (tokens may contain it); blank segments are dropped.
List<CookiePair> parseCookieHeader(String header) {
  final pairs = <CookiePair>[];
  for (final part in header.split(';')) {
    final trimmed = part.trim();
    final eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    pairs.add(CookiePair(
      trimmed.substring(0, eq).trim(),
      trimmed.substring(eq + 1).trim(),
    ));
  }
  return pairs;
}

/// Holds the sign-in prompt a plugin is currently asking to show, for
/// the shell's overlay. The repository's sign-in call brackets the flow
/// with [begin]/[end]; the plugin's prompts land through [show]. After
/// [suppress] (the listener cancelled), late prompts from the plugin's
/// still-running poll loop are ignored until the next [begin].
class SignInPromptController extends ChangeNotifier {
  SignInPromptData? _prompt;
  bool _active = false;
  bool _suppressed = false;

  SignInPromptData? get prompt => _prompt;
  bool get visible => _active && _prompt != null;

  void begin() {
    _active = true;
    _suppressed = false;
    _prompt = const SignInPromptData(text: '正在准备登录…');
    notifyListeners();
  }

  void show(SignInPromptData data) {
    if (!_active || _suppressed) return;
    _prompt = data;
    notifyListeners();
  }

  void suppress() {
    _suppressed = true;
    _prompt = null;
    notifyListeners();
  }

  void end() {
    _active = false;
    _suppressed = false;
    _prompt = null;
    notifyListeners();
  }
}
