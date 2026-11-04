// Renders the game logos (lib/models/game.dart) to PNGs for the iOS widget, which can't draw SVG:
//   ios/PhamiTrackerWidget/Logos/logo-<game>@3x.png  (white on transparent; the widget tints them)
//
// Run: flutter test tool/logo/generate_game_logos_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phamitracker/models/game.dart';

const pixels = 96; // 32pt at @3x

void main() {
  test('generate game logos', () async {
    Directory('ios/PhamiTrackerWidget/Logos').createSync(recursive: true);
    for (final game in Game.values) {
      final info = await vg.loadPicture(SvgStringLoader(game.logoSvg), null);
      // A little breathing room so edge-to-edge marks (VALORANT) don't look cramped.
      final scale = pixels * 0.88 / math.max(info.size.width, info.size.height);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // Centre the logo in the square and paint it white.
      canvas.translate((pixels - info.size.width * scale) / 2, (pixels - info.size.height * scale) / 2);
      canvas.scale(scale);
      canvas.saveLayer(
        Offset.zero & info.size,
        Paint()..colorFilter = const ColorFilter.mode(Color(0xFFFFFFFF), BlendMode.srcIn),
      );
      canvas.drawPicture(info.picture);
      canvas.restore();
      final image = await recorder.endRecording().toImage(pixels, pixels);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('ios/PhamiTrackerWidget/Logos/logo-${game.id}@3x.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }
  });
}
