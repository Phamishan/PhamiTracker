import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/game.dart';
import '../services/changelog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/changelog_dialog.dart';
import '../widgets/common.dart';
import '../widgets/game_logo.dart';
import 'link_account_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: AppText.display(24, weight: FontWeight.w500))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
        children: [
          const SectionTitle('Accounts'),
          for (final game in Game.values) ...[
            _AccountTile(game: game),
            const SizedBox(height: 10),
          ],
          if (defaultTargetPlatform == TargetPlatform.iOS) ...[
            const SectionTitle('Live Activity'),
            const _LiveActivityTile(),
          ],
          const SectionTitle('Widgets'),
          const TrackerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bullet(Icons.bolt_rounded, 'RP Today', 'Points won or lost today, plus matches and W/L.'),
                SizedBox(height: 14),
                _Bullet(Icons.flag_rounded, 'Rank Goal', 'Your goal rank and how far you are from it.'),
                SizedBox(height: 14),
                _Bullet(Icons.show_chart_rounded, 'Climb', 'Your RP/RR over all time, 3 months, 1 month, 14 days or 7 days, with your last 5 matches on the large size.'),
                SizedBox(height: 14),
                _Bullet(Icons.map_rounded, 'Map Rotation', 'Current Apex ranked or pubs map with a live countdown.'),
                SizedBox(height: 14),
                _Bullet(
                  Icons.touch_app_rounded,
                  'Customise',
                  'Long-press a widget → Edit Widget to switch game, chart range or map mode. All widgets also come in lock screen sizes.',
                ),
              ],
            ),
          ),
          const SectionTitle('About'),
          FutureBuilder(
            future: ChangelogService.load(),
            builder: (context, snapshot) => _SettingsTile(
              icon: Icons.info_rounded,
              title: 'About PhamiTracker',
              subtitle: snapshot.data?.isNotEmpty == true ? 'Version ${snapshot.data!.first.version}' : 'Version history',
              onTap: () => showChangelogDialog(context),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            "Data from apexlegendsapi.com and HenrikDev. PhamiTracker isn't endorsed by EA, Respawn or Riot Games.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textFaint, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Filled row with an icon, title and subtitle (same shape as PhamiJam's settings tiles).
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.icon, required this.title, required this.subtitle, this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AppColors.text, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
            ],
          ),
        ),
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
            decoration: BoxDecoration(color: game.glow.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: Center(child: GameLogo(game, size: 22, color: game.glow)),
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
  const _Bullet(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.textFaint),
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

/// Automatic Live Activity: on the lock screen and in the Dynamic Island while you play, started
/// and ended by the worker so you never have to open the app first.
class _LiveActivityTile extends StatelessWidget {
  const _LiveActivityTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final on = state.liveActivityEnabled;
    return TrackerCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_iphone_rounded, color: on ? AppColors.accent : AppColors.textFaint),
              const SizedBox(width: 14),
              const Expanded(child: Text('Show sessions automatically', style: TextStyle(fontWeight: FontWeight.w600))),
              Switch(
                value: on,
                activeThumbColor: AppColors.accent,
                onChanged: (value) async {
                  final ok = await state.setLiveActivityEnabled(value);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Needs iOS 17.2 or newer, with Live Activities allowed for PhamiTracker in iOS Settings.'),
                    ));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Your session appears on the lock screen and in the Dynamic Island when you load into an Apex '
              'match, or after your first VALORANT ranked game, without opening the app. It updates after '
              'every game and ends 45 minutes after your last one. Turning this off stops it completely.',
              style: const TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
