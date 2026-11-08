import 'package:flutter/material.dart';

import '../data/home_repository.dart';
import '../data/models.dart';
import 'library_pages.dart' show PageTitle;
import 'theme.dart';
import 'widgets.dart';

/// Settings, doubling as the phone layout's 我的 page: the account
/// (sign in / out), the plugin's login-method setting, and what the
/// app keeps on the device. The login method is the plugin's own
/// declared setting (qr by default; web shows the service's login page
/// in an in-app browser) — changing it persists and reboots the plugin
/// host, as host.setting() is read at boot.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repository,
    required this.account,
    required this.onSignIn,
    required this.onSignOut,
  });

  final HomeRepository repository;
  final AccountInfo? account;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _loginMethod = 'qr';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.repository.getLoginMethod().then((value) {
      if (!mounted) return;
      setState(() {
        _loginMethod = value == 'web' ? 'web' : 'qr';
        _loaded = true;
      });
    });
  }

  Future<void> _setLoginMethod(String method) async {
    setState(() => _loginMethod = method);
    await widget.repository.setLoginMethod(method);
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 30, pad, 40),
      children: [
        const PageTitle(title: '设置'),
        _accountCard(),
        const SizedBox(height: 28),
        const SectionTitle(title: '登录方式'),
        _methodTile(
          value: 'qr',
          title: '扫码登录',
          line: '用网易云音乐 App 扫一扫（插件默认方式）',
        ),
        _methodTile(
          value: 'web',
          title: '网页登录',
          line: '在应用内打开网易云登录页，登录后自动读取 Cookie',
        ),
        const SizedBox(height: 28),
        const SectionTitle(title: '关于'),
        const Text(
          'easyMusic 1.0.0\n'
          '音乐数据来自音源插件（网易云音乐），播放与登录都在本机完成；'
          '登录状态保存在应用的本地存储里，重启不丢失。',
          style: TextStyle(fontSize: 13, height: 1.6, color: Palette.muted),
        ),
      ],
    );
  }

  Widget _accountCard() {
    final account = widget.account;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Palette.sidebar,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (account != null && account.imageUrl.isNotEmpty)
            CoverImage(
              imageUrl: account.imageUrl,
              size: 46,
              radius: 23,
              iconSize: 20,
            )
          else
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Palette.press,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, size: 24, color: Palette.muted),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account?.name ?? '未登录',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: Palette.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  account != null ? '网易云音乐账号已登录' : '登录后同步歌单、喜欢与每日推荐',
                  style: const TextStyle(fontSize: 12.5, color: Palette.muted),
                ),
              ],
            ),
          ),
          if (account == null)
            FilledButton(
              onPressed: widget.onSignIn,
              style: FilledButton.styleFrom(
                backgroundColor: Palette.accent,
                foregroundColor: Palette.onAccent,
              ),
              child: const Text('登录'),
            )
          else
            OutlinedButton(
              onPressed: widget.onSignOut,
              child: const Text('退出登录'),
            ),
        ],
      ),
    );
  }

  Widget _methodTile({
    required String value,
    required String title,
    required String line,
  }) {
    final selected = _loaded && _loginMethod == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _loaded ? () => _setLoginMethod(value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? Palette.accent : Palette.faint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Palette.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      line,
                      style:
                          const TextStyle(fontSize: 12.5, color: Palette.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
