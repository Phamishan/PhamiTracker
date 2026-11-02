import 'package:flutter/material.dart';

/// The games PhamiTracker can track. Add a value here (plus ranks and a worker poller) to
/// support a new one.
enum Game {
  apex(
    id: 'apex',
    title: 'Apex Legends',
    shortTitle: 'APEX',
    unit: 'RP',
    icon: Icons.local_fire_department_rounded,
    gradient: [Color(0xFFFF2E4D), Color(0xFFFF8A00)],
    glow: Color(0xFFFF5A36),
  ),
  valorant(
    id: 'valorant',
    title: 'VALORANT',
    shortTitle: 'VALORANT',
    unit: 'RR',
    icon: Icons.change_history_rounded,
    gradient: [Color(0xFFFF4655), Color(0xFF8B2CF5)],
    glow: Color(0xFFFF4D8D),
  );

  const Game({
    required this.id,
    required this.title,
    required this.shortTitle,
    required this.unit,
    required this.icon,
    required this.gradient,
    required this.glow,
  });

  final String id;
  final String title;
  final String shortTitle;

  /// What a rank point is called in this game.
  final String unit;
  final IconData icon;
  final List<Color> gradient;
  final Color glow;

  LinearGradient get linearGradient =>
      LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight);

  static Game fromId(String? id) => Game.values.firstWhere((g) => g.id == id, orElse: () => Game.apex);
}

const apexPlatforms = {'PC': 'PC', 'PS4': 'PlayStation', 'X1': 'Xbox', 'SWITCH': 'Switch'};
const valorantRegions = {
  'eu': 'Europe',
  'na': 'North America',
  'ap': 'Asia Pacific',
  'kr': 'Korea',
  'latam': 'LATAM',
  'br': 'Brazil',
};
const valorantPlatforms = {'pc': 'PC', 'console': 'Console'};
