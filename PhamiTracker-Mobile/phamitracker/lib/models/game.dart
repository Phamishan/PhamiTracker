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
    gradient: [Color(0xFFF5A35C), Color(0xFFD9772F)],
    glow: Color(0xFFF08C45),
  ),
  valorant(
    id: 'valorant',
    title: 'VALORANT',
    shortTitle: 'VALORANT',
    unit: 'RR',
    icon: Icons.change_history_rounded,
    gradient: [Color(0xFF9E8CFF), Color(0xFF6B55D9)],
    glow: Color(0xFF8B78F2),
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
