import 'package:flutter/material.dart';

import 'sidebar.dart';
import 'theme.dart';

/// A page the skeleton routes to but v1 has not built yet: an honest empty
/// state in the desktop app's manner — a soft icon tile, a title and one
/// line saying what will be here or what it waits on. Nothing is faked.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.page});

  final AppPage page;

  @override
  Widget build(BuildContext context) {
    final (icon, title, line) = switch (page) {
      AppPage.daily => (
          Icons.calendar_month_outlined,
          '每日推荐',
          '每日推荐需要登录网易云账号，登录功能在后续版本接入。'
        ),
      AppPage.charts => (
          Icons.leaderboard_outlined,
          '排行榜',
          '各榜单歌单已经在首页的「排行榜」区块里了，独立榜单页随后就来。'
        ),
      AppPage.liked => (
          Icons.favorite_border,
          '喜欢的音乐',
          '登录网易云后，你喜欢的歌曲会同步到这里。'
        ),
      AppPage.savedAlbums => (
          Icons.album_outlined,
          '收藏专辑',
          '登录网易云后，你收藏的专辑会同步到这里。'
        ),
      AppPage.stations => (
          Icons.radio_outlined,
          '私人FM',
          '私人 FM 要按你的口味一直接一首地生成，交互方式和普通歌单不同，随后接入。'
        ),
      AppPage.shows => (
          Icons.podcasts_outlined,
          '我的播客',
          '登录网易云后，你订阅的播客会同步到这里。'
        ),
      AppPage.local => (
          Icons.folder_outlined,
          '本地音乐',
          '选择存放音乐的文件夹后，本地歌曲会出现在这里。'
        ),
      AppPage.search => (
          Icons.search,
          '搜索',
          '搜索框与结果页随后接入，插件的搜索在 M0 已经验证可用。'
        ),
      AppPage.settings => (
          Icons.settings_outlined,
          '设置',
          '音源插件、播放与外观设置随后接入。'
        ),
      AppPage.home => (Icons.home_outlined, '发现音乐', ''),
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Palette.hover,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 32, color: Palette.muted),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Palette.text,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              line,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: Palette.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
