import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../data/home_repository.dart';
import '../data/models.dart';
import 'detail_pages.dart';
import 'library_pages.dart' show PageTitle;
import 'theme.dart';
import 'widgets.dart';

/// The search page: a field over kind chips （歌曲/歌单/专辑/歌手/节目）,
/// suggestions while typing, and the plugin's search() results — songs
/// play as a queue, everything else opens its detail page. Loading,
/// empty and failure states are all spelled out; nothing is cached
/// from another query.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.repository, required this.engine});

  final HomeRepository repository;
  final AudioEngine engine;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchKind {
  const _SearchKind(this.id, this.label);
  final String id;
  final String label;
}

const _kinds = <_SearchKind>[
  _SearchKind('tracks', '歌曲'),
  _SearchKind('playlists', '歌单'),
  _SearchKind('albums', '专辑'),
  _SearchKind('artists', '歌手'),
  _SearchKind('shows', '节目'),
];

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _kind = 'tracks';
  String _query = '';
  List<String> _suggestions = const [];
  SearchResults? _results;
  bool _searching = false;
  bool _loadingMore = false;
  Object? _error;
  int _searchSeq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    _debounce?.cancel();
    final query = text.trim();
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _suggestions = const [];
        _results = null;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final found = await widget.repository.suggest(query);
        if (!mounted || _controller.text.trim() != query) return;
        setState(() => _suggestions = found);
      } catch (_) {
        // Suggestions are a nicety; their failure stays silent.
      }
    });
  }

  Future<void> _search(String query, String kind) async {
    final seq = ++_searchSeq;
    setState(() {
      _query = query;
      _kind = kind;
      _searching = true;
      _error = null;
      _suggestions = const [];
    });
    try {
      final results =
          await widget.repository.search(query, kind: kind, offset: 0);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _error = e;
        _searching = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final results = _results;
    if (results == null || _loadingMore || !results.more) return;
    final offset = switch (_kind) {
      'tracks' => results.tracks.length,
      'playlists' => results.playlists.length,
      'albums' => results.albums.length,
      'artists' => results.artists.length,
      _ => results.shows.length,
    };
    setState(() => _loadingMore = true);
    try {
      final next = await widget.repository
          .search(_query, kind: _kind, offset: offset);
      if (!mounted) return;
      setState(() {
        _results = SearchResults(
          kind: _kind,
          tracks: [...results.tracks, ...next.tracks],
          playlists: [...results.playlists, ...next.playlists],
          albums: [...results.albums, ...next.albums],
          artists: [...results.artists, ...next.artists],
          shows: [...results.shows, ...next.shows],
          more: next.more,
        );
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _submit() {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    _search(query, _kind);
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 30, pad, 40),
      children: [
        const PageTitle(title: '搜索', subtitle: '网易云音乐'),
        _field(),
        if (_query.isEmpty && _suggestions.isNotEmpty) _suggestionList(),
        const SizedBox(height: 18),
        _kindChips(),
        const SizedBox(height: 10),
        _body(),
      ],
    );
  }

  Widget _field() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Palette.sidebar,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Palette.hairline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: Palette.faint),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: false,
              textInputAction: TextInputAction.search,
              onChanged: _onTextChanged,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontSize: 14.5, color: Palette.text),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '搜索歌曲、歌单、专辑、歌手',
                hintStyle: TextStyle(fontSize: 14, color: Palette.faint),
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              onPressed: () {
                _controller.clear();
                _onTextChanged('');
              },
              icon: const Icon(Icons.close, size: 17),
              color: Palette.muted,
              splashRadius: 16,
            ),
          TextButton(
            onPressed: _submit,
            child: const Text('搜索',
                style: TextStyle(fontSize: 14, color: Palette.accent)),
          ),
        ],
      ),
    );
  }

  Widget _suggestionList() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in _suggestions)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                _controller.text = s;
                _search(s, _kind);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 15, color: Palette.faint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, color: Palette.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kindChips() {
    return Wrap(
      spacing: 8,
      children: [
        for (final kind in _kinds)
          ChoiceChip(
            label: Text(kind.label),
            selected: _kind == kind.id,
            onSelected: (_) {
              if (_query.isNotEmpty) {
                _search(_query, kind.id);
              } else {
                setState(() => _kind = kind.id);
              }
            },
            selectedColor: Palette.accent.withValues(alpha: 0.14),
            backgroundColor: Palette.sidebar,
            labelStyle: TextStyle(
              fontSize: 13,
              color: _kind == kind.id ? Palette.accent : Palette.text,
              fontWeight:
                  _kind == kind.id ? FontWeight.w600 : FontWeight.w400,
            ),
            side: BorderSide.none,
            showCheckmark: false,
          ),
      ],
    );
  }

  Widget _body() {
    if (_searching) return const LoadingState(line: '正在搜索…');
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: '搜索失败',
        line: '$_error',
        actionLabel: '重试',
        onAction: () => _search(_query, _kind),
      );
    }
    final results = _results;
    if (results == null) {
      return const EmptyState(
        icon: Icons.search,
        title: '搜你想听的',
        line: '输入关键词，歌曲结果点一行就能播。',
      );
    }
    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_outlined,
        title: '没有找到',
        line: '没有找到与「$_query」相关的${_kindLabel()}，换个关键词试试。',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        switch (_kind) {
          'playlists' => PlaylistCardGrid(
              playlists: results.playlists,
              onTap: (p) => openPlaylistDetail(
                context,
                repository: widget.repository,
                engine: widget.engine,
                playlist: p,
              ),
            ),
          'albums' => AlbumCardGrid(
              albums: results.albums,
              onTap: (a) => openAlbumDetail(
                context,
                repository: widget.repository,
                engine: widget.engine,
                album: a,
              ),
            ),
          'artists' => Column(
              children: [
                for (final a in results.artists)
                  ArtistRow(
                    artist: a,
                    onTap: () => openArtistDetail(
                      context,
                      repository: widget.repository,
                      engine: widget.engine,
                      artist: a,
                    ),
                  ),
              ],
            ),
          'shows' => Column(
              children: [
                for (final s in results.shows)
                  ShowRow(
                    show: s,
                    onTap: () => openShowDetail(
                      context,
                      repository: widget.repository,
                      engine: widget.engine,
                      show: s,
                    ),
                  ),
              ],
            ),
          _ => TrackRows(tracks: results.tracks, engine: widget.engine),
        },
        if (results.more)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Center(
              child: OutlinedButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(_loadingMore ? '正在加载…' : '加载更多'),
              ),
            ),
          ),
      ],
    );
  }

  String _kindLabel() =>
      _kinds.firstWhere((k) => k.id == _kind, orElse: () => _kinds.first).label;
}
