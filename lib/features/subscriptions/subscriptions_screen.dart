
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/subscriptions_feed.dart';
import '../../innertube/models.dart';
import '../../providers.dart';
import '../../ui/navigation.dart';
import '../../ui/theme/yt_theme.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/top_bar.dart';
import '../../ui/widgets/video_tiles.dart';

enum _Filter { all, today, videos, shorts, continueWatching, unwatched }

const _labels = {
  _Filter.all: 'Vše',
  _Filter.today: 'Dnes',
  _Filter.videos: 'Videa',
  _Filter.shorts: 'Krátká videa',
  _Filter.continueWatching: 'Pokračovat ve sledování',
  _Filter.unwatched: 'Nepřehraná',
};

class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() =>
      _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    ref.read(subscriptionsFeedServiceProvider).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final subs =
        ref.watch(subscriptionsProvider).value ?? const <ChannelItem>[];
    final feed = ref.watch(subscriptionFeedProvider);
    final progress =
        ref.watch(watchProgressProvider).value ?? const <String, double>{};
    final all = feed.value ?? const <FeedVideo>[];
    final now = DateTime.now();

    final filtered = [
      for (final f in all)
        if (switch (_filter) {
          _Filter.all => true,
          _Filter.today => now.difference(f.publishedAt).inHours < 24,
          _Filter.videos => !f.video.isShort,
          _Filter.shorts => f.video.isShort,
          _Filter.continueWatching =>
            (progress[f.video.id] ?? 0) > 0 &&
                (progress[f.video.id] ?? 0) < 0.9,
          _Filter.unwatched => !progress.containsKey(f.video.id),
        })
          f.video,
    ];

    final videos = filtered
        .where((v) => !v.isShort || _filter == _Filter.shorts)
        .toList();
    final shorts = _filter == _Filter.all
        ? filtered.where((v) => v.isShort).take(12).toList()
        : const <VideoItem>[];

    return Scaffold(
      body: StatusBarScrim(
        child: RefreshIndicator(
          color: context.yt.textPrimary,
          onRefresh: () =>
              ref.read(subscriptionsFeedServiceProvider).refresh(force: true),
          child: CustomScrollView(
            slivers: [
              const YtTopBar(),
              if (subs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyView(
                    icon: Symbols.subscriptions,
                    title: 'Nenechte si ujít nová videa',
                    message:
                        'Odebírejte kanály a jejich nejnovější videa se zobrazí zde. Odběry se ukládají v tomto zařízení.',
                    action: FilledButton(
                      onPressed: () => openSearch(context, ref),
                      child: const Text('Najít kanály'),
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: _ChannelStrip(channels: subs),
                ),
                SliverToBoxAdapter(
                  child: ChipBar(
                    children: [
                      for (final f in _Filter.values)
                        YtChip(
                          label: _labels[f]!,
                          selected: f == _filter,
                          onTap: () => setState(() => _filter = f),
                        ),
                    ],
                  ),
                ),
                if (feed.isLoading && all.isEmpty)
                  const SliverToBoxAdapter(child: FeedSkeleton())
                else if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyView(
                      icon: Symbols.video_library,
                      title: all.isEmpty
                          ? 'Načítání vašich odběrů…'
                          : 'Žádná videa',
                      message: all.isEmpty
                          ? 'Potáhněte dolů pro obnovení.'
                          : 'Zkuste jiný filtr.',
                    ),
                  )
                else if (_filter == _Filter.shorts)
                  SliverPadding(
                    padding: const EdgeInsets.all(8),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        childAspectRatio: 9 / 16,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: videos.length,
                      itemBuilder: (_, i) => LayoutBuilder(
                        builder: (_, box) =>
                            ShortCard(videos[i], width: box.maxWidth),
                      ),
                    ),
                  )
                else
                  VideosWithShortsSliver(
                    videos: videos,
                    shorts: shorts,
                    phoneShelfAt: 1,
                  ),
              ],
              const SliverBottomInset(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vodorovný seznam avatarů kanálů s tlačítkem „Vše“ na konci.
class _ChannelStrip extends ConsumerWidget {
  const _ChannelStrip({required this.channels});

  final List<ChannelItem> channels;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
        height: 96,
        child: Row(
          children: [
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: channels.length,
                itemBuilder: (_, i) => InkWell(
                  onTap: () => openChannel(context, ref, channels[i].id),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 72,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Avatar(
                          channels[i].avatar,
                          size: 56,
                          name: channels[i].name,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          channels[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.yt.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  context.push('${branchPrefix(context)}/channels'),
              style: TextButton.styleFrom(
                foregroundColor: context.yt.link,
              ),
              child: const Text(
                'Vše',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
}

/// Přehled všech odebíraných kanálů.
class ChannelsScreen extends ConsumerWidget {
  const ChannelsScreen({super.key});

  static final extraActions =
      <Widget Function(BuildContext, WidgetRef)>[];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.yt;
    final subscriptions = ref.watch(subscriptionsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Všechny odběry'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Symbols.arrow_back),
        ),
        actions: [
          for (final action in extraActions) action(context, ref),
        ],
      ),
      body: MaxContentWidth(
        child: subscriptions.when(
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (error, stackTrace) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.error_outline,
                    size: 42,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Odběry se nepodařilo načíst',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$error',
                    style: TextStyle(color: colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          data: (subs) {
            if (subs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Symbols.subscriptions,
                      size: 48,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Zatím nemáte žádné odběry',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Row(
                    children: [
                      Text(
                        'Odebírané kanály',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.chip,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${subs.length}',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: subs.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 76,
                      color: colors.divider,
                    ),
                    itemBuilder: (context, i) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: Avatar(
                        subs[i].avatar,
                        size: 48,
                        name: subs[i].name,
                      ),
                      title: Text(
                        subs[i].name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: Icon(
                        Symbols.chevron_right,
                        color: colors.textSecondary,
                      ),
                      onTap: () =>
                          openChannel(context, ref, subs[i].id),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
