import 'package:flutter/material.dart';

/// The games PhamiTracker can track. Add a value here (plus ranks and a worker poller) to
/// support a new one.
enum Game {
  apex(
    id: 'apex',
    title: 'Apex Legends',
    shortTitle: 'APEX',
    unit: 'RP',
    logoSvg: _apexLogo,
    gradient: [Color(0xFFEF6A4F), Color(0xFFC9402C)],
    glow: Color(0xFFE0604E),
  ),
  valorant(
    id: 'valorant',
    title: 'VALORANT',
    shortTitle: 'VALORANT',
    unit: 'RR',
    logoSvg: _valorantLogo,
    gradient: [Color(0xFFFF5A67), Color(0xFFD63A48)],
    glow: Color(0xFFFF4655),
  );

  const Game({
    required this.id,
    required this.title,
    required this.shortTitle,
    required this.unit,
    required this.logoSvg,
    required this.gradient,
    required this.glow,
  });

  final String id;
  final String title;
  final String shortTitle;

  /// What a rank point is called in this game.
  final String unit;

  /// The game's mark as a single-colour SVG (tinted by [GameLogo]).
  final String logoSvg;
  final List<Color> gradient;
  final Color glow;

  LinearGradient get linearGradient =>
      LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight);

  static Game fromId(String? id) => Game.values.firstWhere((g) => g.id == id, orElse: () => Game.apex);
}

// The Apex "A" emblem, traced from the CC0 file on Wikimedia Commons
// (File:Apex_legends_simple_logo.jpg). Apex Legends is a trademark of Electronic Arts.
const _apexLogo = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 264 251">'
    '<path d="M132 0L264 216L230 251L154 201L196 201L132 106L68 201L110 201L34 251L0 216Z"/></svg>';

// The VALORANT mark from Simple Icons (CC0, simpleicons.org). VALORANT is a trademark of Riot Games.
const _valorantLogo = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M23.792 2.152a.252.252 0 0 0-.098.083'
    'c-3.384 4.23-6.769 8.46-10.15 12.69-.107.093-.025.288.119.265 2.439.003 4.877 0 7.316.001a.66.66 0 0 0 .552-.25'
    'c.774-.967 1.55-1.934 2.324-2.903a.72.72 0 0 0 .144-.49c-.002-3.077 0-6.153-.003-9.23.016-.11-.1-.206-.204-.167z'
    'M.077 2.166c-.077.038-.074.132-.076.205.002 3.074.001 6.15.001 9.225a.679.679 0 0 0 .158.463l7.64 9.55'
    'c.12.152.308.25.505.247 2.455 0 4.91.003 7.365 0 .142.02.222-.174.116-.265C10.661 15.176 5.526 8.766.4 2.35'
    'c-.08-.094-.174-.272-.322-.184z"/></svg>';

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
