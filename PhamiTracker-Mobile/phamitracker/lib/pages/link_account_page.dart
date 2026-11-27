import 'package:flutter/material.dart';

import '../models/game.dart';
import '../services/tracker_api.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/game_logo.dart';
import 'home_page.dart';

/// Link (or replace) the account tracked for one game.
class LinkAccountPage extends StatefulWidget {
  const LinkAccountPage({super.key, required this.game});

  final Game game;

  @override
  State<LinkAccountPage> createState() => _LinkAccountPageState();
}

class _LinkAccountPageState extends State<LinkAccountPage> {
  final _name = TextEditingController();
  final _tag = TextEditingController();
  late String _platform = widget.game.defaultPlatform;
  late String _region = widget.game.defaultRegion(WidgetsBinding.instance.platformDispatcher.locale.countryCode) ?? 'eu';
  bool _busy = false;
  String? _error;

  Game get game => widget.game;

  @override
  void dispose() {
    _name.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    var name = _name.text.trim();
    var tag = _tag.text.trim().replaceFirst('#', '');
    // Accept "Name#TAG" pasted into the name field.
    if (game.hasRiotId && name.contains('#') && tag.isEmpty) {
      final parts = name.split('#');
      name = parts.first.trim();
      tag = parts.last.trim();
    }
    if (name.isEmpty || (game.hasRiotId && tag.isEmpty)) {
      setState(() => _error = game.hasRiotId ? 'Enter your Riot ID and tag.' : 'Enter your player name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).link(
        game: game,
        name: name,
        tag: game.hasRiotId ? tag : null,
        platform: _platform,
        region: game.regions != null ? _region : null,
      );
      if (mounted) Navigator.of(context).pop();
    } on TrackerApiException catch (e) {
      setState(() => _error = e.statusCode == 404 ? "Couldn't find that account. Check the spelling and platform." : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final platforms = game.platforms;
    return Scaffold(
      appBar: AppBar(title: Text('Link ${game.title}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Container(
            height: 120,
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
            child: Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: game.glow.withValues(alpha: 0.16), shape: BoxShape.circle),
                child: Center(child: GameLogo(game, size: 40, color: game.glow)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _name,
                  autocorrect: false,
                  textInputAction: game.hasRiotId ? TextInputAction.next : TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: game == Game.apex ? 'Player name (EA / console name)' : 'Riot ID',
                    prefixIcon: const Icon(Icons.person_rounded),
                  ),
                  onSubmitted: (_) => game.hasRiotId ? null : _submit(),
                ),
              ),
              if (game.hasRiotId) ...[
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _tag,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Tag', prefixText: '#'),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ],
            ],
          ),
          SectionTitle(game.platformLabel),
          OptionChips(options: platforms, selected: _platform, game: game, onSelected: (v) => setState(() => _platform = v)),
          if (game.regions case final regions?) ...[
            SectionTitle(game.regionLabel),
            OptionChips(options: regions, selected: _region, game: game, onSelected: (v) => setState(() => _region = v)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 18),
            Text(_error!, style: const TextStyle(color: AppColors.loss, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 28),
          GradientButton(game: game, label: 'Start tracking', busy: _busy, onPressed: _submit),
          const SizedBox(height: 14),
          Text(
            switch (game) {
              Game.apex => 'Use the name on the platform you play ranked on. Crossplay players: use your EA name with PC.',
              Game.valorant => 'Matches from before you link are backfilled from your recent ranked history.',
              Game.lol => 'Pick the queue to follow: Solo/Duo and Flex are separate ranks. Games are recorded from now on.',
            },
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// A row of choice chips (platform, region), tinted with the game colour.
class OptionChips extends StatelessWidget {
  const OptionChips({super.key, required this.options, required this.selected, required this.game, required this.onSelected});

  final Map<String, String> options;
  final String selected;
  final Game game;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final MapEntry(:key, :value) in options.entries)
          ChoiceChip(
            label: Text(value),
            selected: key == selected,
            onSelected: (_) => onSelected(key),
            selectedColor: game.glow.withValues(alpha: 0.25),
            side: BorderSide(color: key == selected ? game.glow : AppColors.border),
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: key == selected ? Colors.white : AppColors.textDim),
            showCheckmark: false,
          ),
      ],
    );
  }
}
