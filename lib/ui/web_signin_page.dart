import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../plugin/sign_in.dart';
import 'theme.dart';

/// The host.webSignIn page: shows the plugin's login page in a web
/// view (the plugin's own User-Agent), polls the platform cookie store
/// of the address the plugin named, and pops with the Cookie header
/// once every awaited cookie exists — the desktop host's rule.
///
/// The cookie read goes through the app's own platform channel
/// (MainActivity's `getCookies`, android.webkit.CookieManager), which
/// sees HttpOnly cookies like MUSIC_U that document.cookie cannot.
/// Off Android the channel is absent, checks simply never complete,
/// and the page gives up at the five-minute limit — the QR flow is
/// the cross-platform path. Closing the page early pops null.
class WebSignInPage extends StatefulWidget {
  const WebSignInPage({super.key, required this.request});

  final WebSignInRequest request;

  @override
  State<WebSignInPage> createState() => _WebSignInPageState();
}

class _WebSignInPageState extends State<WebSignInPage> {
  static const _channel =
      MethodChannel('club.easymusic.easymusic/media_store');

  late final WebViewController _controller;
  Timer? _poll;
  Timer? _timeout;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    if (widget.request.userAgent.isNotEmpty) {
      _controller.setUserAgent(widget.request.userAgent);
    }
    _controller.loadRequest(Uri.parse(widget.request.url));
    _poll = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _checkCookies(),
    );
    _timeout = Timer(const Duration(minutes: 5), () => _finish(null));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _timeout?.cancel();
    super.dispose();
  }

  Future<void> _checkCookies() async {
    if (_finished) return;
    try {
      final header = await _channel.invokeMethod<String>(
            'getCookies',
            widget.request.cookiesOf,
          ) ??
          '';
      final cookie = buildCookieHeader(
        parseCookieHeader(header),
        widget.request.until,
      );
      if (cookie != null) _finish(cookie);
    } catch (_) {
      // No channel on this platform (or the store is not ready):
      // the next tick tries again.
    }
  }

  void _finish(String? cookie) {
    if (_finished || !mounted) return;
    _finished = true;
    Navigator.of(context).pop(cookie);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Palette.text),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '取消登录',
          onPressed: () => _finish(null),
        ),
        title: const Text(
          '登录网易云音乐',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Palette.text,
          ),
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
