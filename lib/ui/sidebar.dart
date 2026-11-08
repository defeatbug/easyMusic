import 'package:flutter/material.dart';

import '../data/models.dart';
import 'theme.dart';
import 'widgets.dart' show CoverImage;

/// Pages the shell can show. The first block mirrors the NetEase plugin's
/// declared navigation, as the desktop sidebar does.
enum AppPage {
  home,
  daily,
  charts,
  liked,
  savedAlbums,
  stations,
  shows,
  local,
  search,
  settings,
}

class NavEntry {
  const NavEntry(this.page, this.icon, this.label);
  final AppPage page;
  final IconData icon;
  final String label;
}

const navEntries = <NavEntry>[
  NavEntry(AppPage.home, Icons.home_outlined, '发现音乐'),
  NavEntry(AppPage.daily, Icons.calendar_month_outlined, '每日推荐'),
  NavEntry(AppPage.charts, Icons.leaderboard_outlined, '排行榜'),
  NavEntry(AppPage.liked, Icons.favorite_border, '喜欢的音乐'),
  NavEntry(AppPage.savedAlbums, Icons.album_outlined, '收藏专辑'),
  NavEntry(AppPage.stations, Icons.radio_outlined, '私人FM'),
  NavEntry(AppPage.shows, Icons.podcasts_outlined, '我的播客'),
  NavEntry(AppPage.local, Icons.folder_outlined, '本地音乐'),
];

/// The desktop sidebar, 232 wide: the source's name, a search field, the
/// navigation the plugin declares, the listener's playlists, and the
/// account row along the foot. Below a narrow window width it collapses
/// to a 64-wide icon rail ([rail] = true).
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.rail,
    this.account,
    this.playlists = const [],
    this.onAccountTap,
    this.onSignOut,
    this.onOpenPlaylist,
  });

  final AppPage selected;
  final void Function(AppPage page) onSelect;
  final bool rail;

  /// The signed-in account, or null. The account row and the 我的歌单
  /// section follow it.
  final AccountInfo? account;

  /// The listener's playlists, shown under 我的歌单 once signed in.
  final List<PlaylistItem> playlists;
  final VoidCallback? onAccountTap;
  final VoidCallback? onSignOut;
  final void Function(PlaylistItem playlist)? onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: rail ? 64 : sidebarWidth,
      color: Palette.sidebar,
      child: Column(
        crossAxisAlignment:
            rail ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(rail ? 0 : 14, 16, rail ? 0 : 14, 6),
            child: rail ? _sourceMark() : _sourceRow(),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(rail ? 8 : 14, 6, rail ? 8 : 14, 10),
            child: _searchField(context),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: rail ? 8 : 14),
              children: [
                for (final e in navEntries) _navItem(e),
                if (!rail) ...[
                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(10, 0, 10, 6),
                    child: Row(
                      children: [
                        Text(
                          '我的歌单',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Palette.faint,
                          ),
                        ),
                        Spacer(),
                        Icon(Icons.add, size: 15, color: Palette.faint),
                      ],
                    ),
                  ),
                  if (account == null)
                    GestureDetector(
                      onTap: onAccountTap,
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(10, 2, 10, 2),
                        child: Text(
                          '登录后同步你的歌单',
                          style: TextStyle(fontSize: 12.5, color: Palette.faint),
                        ),
                      ),
                    )
                  else if (playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(10, 2, 10, 2),
                      child: Text(
                        '还没有歌单',
                        style: TextStyle(fontSize: 12.5, color: Palette.faint),
                      ),
                    )
                  else
                    for (final p in playlists.take(12)) _playlistRow(p),
                ],
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Palette.hairline),
          Padding(
            padding: EdgeInsets.fromLTRB(rail ? 0 : 14, 10, rail ? 0 : 14, 12),
            child: rail ? _accountRail() : _accountRow(),
          ),
        ],
      ),
    );
  }

  Widget _sourceMark() {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Palette.accent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.music_note, size: 17, color: Palette.onAccent),
    );
  }

  Widget _sourceRow() {
    return Row(
      children: [
        _sourceMark(),
        const SizedBox(width: 9),
        const Text(
          '网易云音乐',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Palette.muted,
          ),
        ),
        const Spacer(),
        const Icon(Icons.unfold_more, size: 13, color: Palette.faint),
      ],
    );
  }

  Widget _searchField(BuildContext context) {
    return GestureDetector(
      onTap: () => onSelect(AppPage.search),
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: Palette.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Palette.hairline),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment:
              rail ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            const Icon(Icons.search, size: 15, color: Palette.faint),
            if (!rail) ...[
              const SizedBox(width: 7),
              const Text(
                '搜索',
                style: TextStyle(fontSize: 13, color: Palette.faint),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _navItem(NavEntry e) {
    final isSelected = selected == e.page;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? Palette.press : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onSelect(e.page),
          child: Container(
            height: 34,
            padding: EdgeInsets.symmetric(horizontal: rail ? 0 : 10),
            child: Row(
              mainAxisAlignment:
                  rail ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(
                  e.icon,
                  size: 18,
                  color: isSelected ? Palette.accent : Palette.text,
                ),
                if (!rail) ...[
                  const SizedBox(width: 10),
                  Text(
                    e.label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: Palette.text,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _playlistRow(PlaylistItem p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onOpenPlaylist?.call(p),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                const Icon(Icons.queue_music,
                    size: 16, color: Palette.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Palette.text,
                    ),
                  ),
                ),
                if (p.trackCount > 0)
                  Text(
                    '${p.trackCount}',
                    style:
                        const TextStyle(fontSize: 11.5, color: Palette.faint),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountRow() {
    final account = this.account;
    return Row(
      children: [
        GestureDetector(
          onTap: account == null ? onAccountTap : null,
          child: account != null && account.imageUrl.isNotEmpty
              ? CoverImage(
                  imageUrl: account.imageUrl,
                  size: 28,
                  radius: 14,
                  iconSize: 14,
                )
              : Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Palette.press,
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.person, size: 16, color: Palette.muted),
                ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: GestureDetector(
            onTap: account == null ? onAccountTap : null,
            child: Text(
              account?.name ?? '未登录',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Palette.text),
            ),
          ),
        ),
        if (account != null)
          IconButton(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout, size: 16),
            color: Palette.muted,
            splashRadius: 16,
            tooltip: '退出登录',
          ),
        IconButton(
          onPressed: () => onSelect(AppPage.settings),
          icon: const Icon(Icons.settings_outlined, size: 18),
          color: selected == AppPage.settings ? Palette.accent : Palette.muted,
          splashRadius: 16,
          tooltip: '设置',
        ),
      ],
    );
  }

  Widget _accountRail() {
    final account = this.account;
    return Column(
      children: [
        GestureDetector(
          onTap: account == null ? onAccountTap : null,
          child: account != null && account.imageUrl.isNotEmpty
              ? CoverImage(
                  imageUrl: account.imageUrl,
                  size: 28,
                  radius: 14,
                  iconSize: 14,
                )
              : Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Palette.press,
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.person, size: 16, color: Palette.muted),
                ),
        ),
        IconButton(
          onPressed: () => onSelect(AppPage.settings),
          icon: const Icon(Icons.settings_outlined, size: 18),
          color: selected == AppPage.settings ? Palette.accent : Palette.muted,
          splashRadius: 16,
          tooltip: '设置',
        ),
      ],
    );
  }
}
