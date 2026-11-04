import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/game_logo.dart';
import 'link_account_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
        children: [
          const SectionTitle('Accounts'),
          for (final game in Game.values) ...[
            _AccountTile(game: game),
            const SizedBox(height: 10),
          ],
          const SectionTitle('Widgets'),
          const TrackerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bullet(Icons.bolt_rounded, AppColors.accent, 'RP Today', 'Points won or lost today, plus matches and W/L.'),
                SizedBox(height: 14),
                _Bullet(Icons.flag_rounded, AppColors.goal, 'Rank Goal', 'A progress ring towards the goal you set.'),
                SizedBox(height: 14),
                _Bullet(Icons.show_chart_rounded, AppColors.accent, 'Climb', 'Your RP/RR over all time, 3 months, 1 month, 14 days or 7 days, with your last 5 matches on the large size.'),
                SizedBox(height: 14),
                _Bullet(Icons.map_rounded, AppColors.goal, 'Map Rotation', 'Current Apex ranked or pubs map with a live countdown.'),
                SizedBox(height: 14),
                _Bullet(
                  Icons.touch_app_rounded,
                  AppColors.goal,
                  'Pick a game',
                  'Long-press a widget → Edit Widget to switch game, chart range or map mode. All widgets also come in lock screen sizes, and refresh themselves from the cloud tracker.',
                ),
              ],
            ),
          ),
          const SectionTitle('About'),
          TrackerCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.new_releases_rounded, color: AppColors.accent),
                  title: const Text("What's new", style: TextStyle(fontWeight: FontWeight.w700)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangelogPage())),
                ),
                const Divider(height: 1, color: AppColors.border),
                ListTile(
                  leading: Icon(
                    Icons.cloud_done_rounded,
                    color: state.api.config.isConfigured ? AppColors.gain : AppColors.loss,
                  ),
                  title: const Text('Cloud tracker', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    state.api.config.isConfigured ? Uri.parse(state.api.config.baseUrl).host : 'Not configured',
                    style: const TextStyle(color: AppColors.textDim),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Data from apexlegendsapi.com and HenrikDev. PhamiTracker isn\'t endorsed by EA, Respawn or Riot Games.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final account = state.accounts[game];
    final subtitle = account == null
        ? 'Not linked'
        : [
            account.displayName,
            game == Game.apex ? apexPlatforms[account.platform] : valorantRegions[account.region],
          ].nonNulls.join(' · ');

    return TrackerCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(gradient: game.linearGradient, borderRadius: BorderRadius.circular(14)),
            child: Center(child: GameLogo(game, size: 22, color: Colors.white)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(game.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(subtitle, style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LinkAccountPage(game: game))),
            child: Text(account == null ? 'Link' : 'Change', style: TextStyle(color: game.glow, fontWeight: FontWeight.w800)),
          ),
          if (account != null)
            IconButton(
              tooltip: 'Unlink',
              icon: const Icon(Icons.link_off_rounded, color: AppColors.textDim),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Unlink ${game.title}?'),
                    content: const Text('Tracking stops and your recorded matches for this account are deleted.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Unlink', style: TextStyle(color: AppColors.loss)),
                      ),
                    ],
                  ),
                );
                if (ok == true) await state.unlink(game);
              },
            ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.icon, this.color, this.title, this.body);

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(color: AppColors.textDim, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shows assets/CHANGELOG.md (copied from the repo README by Codemagic on every build).
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("What's new", style: TextStyle(fontWeight: FontWeight.w900))),
      body: FutureBuilder(
        future: rootBundle.loadString('assets/CHANGELOG.md'),
        builder: (context, snapshot) {
          final lines = (snapshot.data ?? '').split('\n');
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
              for (final line in lines)
                if (line.startsWith('#'))
                  Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 6),
                    child: Text(
                      line.replaceFirst(RegExp(r'^#+\s*'), ''),
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: line.startsWith('##') ? 17 : 22),
                    ),
                  )
                else if (line.trim().isNotEmpty && !line.startsWith('```'))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      line.replaceFirst(RegExp(r'^\s*[-*]\s+'), '•  ').replaceAll('**', '').replaceAll('`', ''),
                      style: const TextStyle(color: AppColors.textDim, height: 1.4),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
