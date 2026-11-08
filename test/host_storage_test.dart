import 'dart:convert';
import 'dart:io';

import 'package:easymusic/data/json_file_store.dart';
import 'package:easymusic/plugin/sign_in.dart';
import 'package:easymusic/plugin_host.dart';
import 'package:flutter_test/flutter_test.dart';

/// Host-level tests: the JSON store behind storage persistence, the
/// network allowlist matcher, the cookie-header rule, and — booting
/// the real QuickJS host like the capture tool does — storage
/// surviving a host restart and the webSignIn bridge round trip.
///
/// Run with the flutter_js library on the loader path:
///   LD_LIBRARY_PATH=$HOME/.pub-cache/hosted/pub.dev/flutter_js-0.8.7/linux/shared \
///     flutter test test/host_storage_test.dart
void main() {
  group('JsonFileStore', () {
    test('round-trips a map through disk', () async {
      final dir = await Directory.systemTemp.createTemp('store_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/nested/store.json');
      final store = JsonFileStore(file);
      expect(await store.load(), isEmpty);
      await store.save({'session': {'cookie': 'MUSIC_U=x'}, 'n': 3});
      expect(await JsonFileStore(file).load(), {
        'session': {'cookie': 'MUSIC_U=x'},
        'n': 3,
      });
    });

    test('a corrupt file reads as empty instead of throwing', () async {
      final dir = await Directory.systemTemp.createTemp('store_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/store.json');
      await file.writeAsString('this is not json {');
      expect(await JsonFileStore(file).load(), isEmpty);
    });
  });

  group('isHostAllowed', () {
    const allow = {'music.163.com', 'interface.music.163.com'};

    test('declared hosts and their subdomains pass', () {
      expect(isHostAllowed('music.163.com', allow), isTrue);
      expect(isHostAllowed('interface.music.163.com', allow), isTrue);
      expect(isHostAllowed('api.music.163.com', allow), isTrue);
      expect(isHostAllowed('MUSIC.163.COM', allow), isTrue);
    });

    test('undeclared hosts and lookalikes are refused', () {
      expect(isHostAllowed('example.com', allow), isFalse);
      expect(isHostAllowed('music.163.com.evil.com', allow), isFalse);
      expect(isHostAllowed('notmusic.163.com', allow), isFalse);
      expect(isHostAllowed('163.com', allow), isFalse);
    });

    test('an empty allowlist allows nothing extra to be inferred', () {
      // The host treats empty as "nothing declared to enforce", which
      // the matcher itself reports as no-match.
      expect(isHostAllowed('music.163.com', const <String>{}), isFalse);
    });
  });

  group('buildCookieHeader', () {
    test('answers all cookies once the awaited names exist', () {
      final header = buildCookieHeader(
        const [
          CookiePair('MUSIC_U', 'u123'),
          CookiePair('__csrf', 'c9'),
          CookiePair('EMPTY', ''),
        ],
        const ['MUSIC_U'],
      );
      expect(header, 'MUSIC_U=u123; __csrf=c9');
    });

    test('missing an awaited cookie means not signed in yet', () {
      expect(
        buildCookieHeader(
          const [CookiePair('__csrf', 'c9')],
          const ['MUSIC_U'],
        ),
        isNull,
      );
    });

    test('an empty-valued awaited cookie does not count', () {
      expect(
        buildCookieHeader(
          const [CookiePair('MUSIC_U', '')],
          const ['MUSIC_U'],
        ),
        isNull,
      );
    });

    test('parseCookieHeader splits a store header back into pairs', () {
      final pairs = parseCookieHeader('MUSIC_U=ab==; __csrf=c9; ; NMTID=x');
      expect(pairs.map((p) => p.name), ['MUSIC_U', '__csrf', 'NMTID']);
      expect(pairs.first.value, 'ab==');
      expect(
        buildCookieHeader(pairs, const ['MUSIC_U']),
        'MUSIC_U=ab==; __csrf=c9; NMTID=x',
      );
    });
  });

  group('SignInPromptController', () {
    test('prompts show only while active, and suppress sticks', () {
      final controller = SignInPromptController();
      controller.show(const SignInPromptData(qr: 'x', text: 'hi'));
      expect(controller.visible, isFalse); // not begun yet
      controller.begin();
      expect(controller.visible, isTrue);
      expect(controller.prompt?.text, '正在准备登录…');
      controller.show(const SignInPromptData(qr: 'qr-url', text: '请扫码'));
      expect(controller.prompt?.qr, 'qr-url');
      controller.suppress();
      expect(controller.visible, isFalse);
      controller.show(const SignInPromptData(qr: 'late', text: '迟到'));
      expect(controller.visible, isFalse); // a cancelled flow stays down
      controller.end();
      controller.begin();
      expect(controller.visible, isTrue); // next flow starts clean
    });
  });

  group('PluginHost with a storage file', () {
    const plugin = '''
export async function account() {
  host.storage.set("deviceId", "dev-123");
  host.storage.set("session", { cookie: "MUSIC_U=abc", account: { id: "42", name: "测试用户" } });
  return { id: "42", name: "测试用户" };
}
export async function liked() {
  return { device: host.storage.get("deviceId"), session: host.storage.get("session") };
}
export async function search() {
  try {
    const r = await fetch("https://example.com/steal");
    return { status: r.status };
  } catch (e) {
    return { error: String((e && e.message) || e) };
  }
}
export async function signIn() {
  const r = await host.webSignIn({
    url: "https://music.163.com/#/login",
    cookiesOf: "https://music.163.com/",
    until: ["MUSIC_U"],
    userAgent: "test-agent",
  });
  return { cookie: r.cookie };
}
''';

    Future<String> bootstrap() =>
        File('assets/bootstrap.js').readAsString();

    test('storage survives a host restart (the sign-in session)',
        () async {
      final dir = await Directory.systemTemp.createTemp('host_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/plugin_storage.json');

      final first = PluginHost(storageFile: file);
      await first.init(bootstrapSource: await bootstrap());
      first.loadPlugin(plugin);
      final wrote = await first.call('account', const {});
      expect(wrote['ok'], isTrue);
      first.dispose();

      // Persistence is a chained async write; wait for it to land.
      for (var i = 0; i < 40 && !await file.exists(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(await file.exists(), isTrue);
      final onDisk =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(onDisk['deviceId'], 'dev-123');
      expect((onDisk['session'] as Map)['cookie'], 'MUSIC_U=abc');

      final second = PluginHost(storageFile: file);
      addTearDown(second.dispose);
      await second.init(bootstrapSource: await bootstrap());
      second.loadPlugin(plugin);
      final read = await second.call('liked', const {});
      expect(read['ok'], isTrue);
      final result = (read['result'] as Map).cast<String, dynamic>();
      expect(result['device'], 'dev-123');
      expect((result['session'] as Map)['cookie'], 'MUSIC_U=abc');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('the fetch bridge refuses hosts the plugin did not declare',
        () async {
      final host = PluginHost()
        ..networkAllowlist = {'music.163.com', 'interface.music.163.com'};
      addTearDown(host.dispose);
      await host.init(bootstrapSource: await bootstrap());
      host.loadPlugin(plugin);
      final res = await host.call('search', const {});
      expect(res['ok'], isTrue);
      final result = (res['result'] as Map).cast<String, dynamic>();
      expect(result['error'], contains('网络权限'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('webSignIn round-trips through the app handler', () async {
      WebSignInRequest? seen;
      final host = PluginHost()
        ..networkAllowlist = {'music.163.com'}
        ..webSignInHandler = (request) async {
          seen = request;
          return 'MUSIC_U=u123; __csrf=c9';
        };
      addTearDown(host.dispose);
      await host.init(bootstrapSource: await bootstrap());
      host.loadPlugin(plugin);
      final res = await host.call('signIn', const {});
      expect(res['ok'], isTrue);
      expect((res['result'] as Map)['cookie'], 'MUSIC_U=u123; __csrf=c9');
      expect(seen?.cookiesOf, 'https://music.163.com/');
      expect(seen?.until, ['MUSIC_U']);
      expect(seen?.userAgent, 'test-agent');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('webSignIn is refused for a cookie address outside the '
        'declared network permission', () async {
      final host = PluginHost()
        ..networkAllowlist = {'music.163.com'}
        ..webSignInHandler = (_) async => 'MUSIC_U=x';
      addTearDown(host.dispose);
      await host.init(bootstrapSource: await bootstrap());
      host.loadPlugin('''
export async function signIn() {
  const r = await host.webSignIn({
    url: "https://evil.example.com/login",
    cookiesOf: "https://evil.example.com/",
    until: ["MUSIC_U"],
  });
  return { cookie: r.cookie };
}
''');
      final res = await host.call('signIn', const {});
      expect(res['ok'], isFalse);
      expect(res['error'], contains('网络权限'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
