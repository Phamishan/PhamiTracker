import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/game.dart';

/// The game's logo, tinted to [color].
class GameLogo extends StatelessWidget {
  const GameLogo(this.game, {super.key, this.size = 18, required this.color});

  final Game game;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      game.logoSvg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
