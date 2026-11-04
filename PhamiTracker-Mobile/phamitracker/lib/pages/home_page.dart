import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/summary.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/game_logo.dart';
import '../widgets/game_switcher.dart';
import '../widgets/history_chart.dart';
import '../widgets/match_list.dart';
import '../widgets/rank_hero.dart';
import '../widgets/stat_tiles.dart';
import 'goal_sheet.dart';
import 'link_account_page.dart';
import 'search_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppLifecycleListener _lifecycle;
  AppState? _state;

  @override
  void initState() {
    super.initState();
    // Only refresh on a timer while the app is on screen; the worker covers the rest.
    _lifecycle = AppLifecycleListener(
      onResume: () => _state?.startLive(),
      onPause: () => _state?.stopLive(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (!identical(state, _state)) {
      _state = state;
      WidgetsBinding.instance.addPostFrameCallback((_) => state.startLive());
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _state?.stopLive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final game = state.game;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: game.glow,
              onRefresh: state.refreshAll,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
                    sliver: SliverList.list(
                      children: [
                        _Header(name: (state.account ?? state.accounts.values.firstOrNull)?.name, game: game),
                        const SizedBox(height: 18),
                        GameSwitcher(
                          selected: game,
                          linked: state.accounts.keys.toSet(),
                          onChanged: state.selectGame,
                        ),
                        const SizedBox(height: 18),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOutCubic,
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(animation),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey(game),
                            child: state.account == null ? _LinkPrompt(game: game) : _Dashboard(state: state),
                          ),
                        ),
                        if (game == Game.apex && state.apexMaps != null) ...[
                          const SectionTitle('Map Rotation'),
                          RotationCard(rotation: state.apexMaps!),
                        ],
                      ],
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
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final game = state.game;
    final summary = state.summary;
    final account = state.account!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error != null) ...[
          _ErrorBanner(message: state.error!),
          const SizedBox(height: 12),
        ],
        RankHero(game: game, summary: summary, accountName: account.displayName),
        const SizedBox(height: 12),
        GoalCard(game: game, goal: state.goal, summary: summary, onTap: () => showGoalSheet(context, game)),
        const SizedBox(height: 12),
        TodayTile(game: game, today: summary?.today ?? const TodayStats()),
        const SectionTitle('Your Climb'),
        HistoryChart(
          game: game,
          history: state.climb(game),
          range: state.climbRange(game),
          onRange: (range) => state.setClimbRange(game, range),
          goal: state.goal,
        ),
        if (summary != null && summary.maps.isNotEmpty) ...[
          const SectionTitle('By Map'),
          MapStatsCard(game: game, maps: summary.maps),
        ],
        SectionTitle(
          summary == null || summary.matches.isEmpty ? 'Recent Matches' : 'Recent Matches · ${summary.matches.length}',
          trailing: state.isLoading(game)
              ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: game.glow))
              : null,
        ),
        MatchList(game: game, matches: summary?.matches ?? const []),
      ],
    );
  }
}

/// "Welcome back, Phami" with round search and settings buttons, like PhamiJam's home header.
class _Header extends StatelessWidget {
  const _Header({required this.name, required this.game});

  final String? name;
  final Game game;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name == null ? 'Welcome to PhamiTracker' : 'Welcome back, $name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.display(26, weight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 12),
        _RoundButton(
          icon: Icons.search_rounded,
          tooltip: 'Search player',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchPage(initialGame: game))),
        ),
        const SizedBox(width: 8),
        _RoundButton(
          icon: Icons.settings_rounded,
          tooltip: 'Settings',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surfaceHigh,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(dimension: 48, child: Icon(icon, color: AppColors.text)),
        ),
      ),
    );
  }
}

class _LinkPrompt extends StatelessWidget {
  const _LinkPrompt({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    return TrackerCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GameLogo(game, size: 40, color: game.glow),
          const SizedBox(height: 14),
          Text('TRACK YOUR ${game.title.toUpperCase()} RANK', style: AppText.display(22)),
          const SizedBox(height: 8),
          Text(
            'Link your account and every ranked game is logged in the cloud, minute by minute, '
            'even when the app is closed. Then set a goal and add the widgets to your home screen.',
            style: const TextStyle(color: AppColors.textDim, height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              game: game,
              label: 'Link ${game.title} account',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => LinkAccountPage(game: game)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.loss.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.loss.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_tethering_error_rounded, color: AppColors.loss),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.game, required this.label, required this.onPressed, this.busy = false});

  final Game game;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(color: game.glow, borderRadius: BorderRadius.circular(16)),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: busy ? null : onPressed,
            child: SizedBox(
              height: 54,
              child: Center(
                child: busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text(label.toUpperCase(), style: AppText.label(color: Colors.white, size: 14)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
