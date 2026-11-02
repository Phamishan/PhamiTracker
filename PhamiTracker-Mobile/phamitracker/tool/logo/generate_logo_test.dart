// Draws the PhamiTracker logo and writes:
//   assets/images/P.png       app icon (letter on the dark neon background)
//   assets/images/p-trans.png letter only, transparent (splash + iOS dark/tinted icons)
//
// Run:  flutter test tool/logo/generate_logo_test.dart
// Then: dart run flutter_launcher_icons && dart run flutter_native_splash:create
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const size = 1024.0;

// Same palette as the app: Apex red/orange into VALORANT violet.
const metal = [Color(0xFFFFD18A), Color(0xFFFF8A00), Color(0xFFFF2E4D), Color(0xFFD4146A), Color(0xFF8B2CF5)];
const depth = Color(0xFF2A0820);

/// The letter, on a 1000x1000 grid: a bladed stem, a sweeping bowl and a spur, in the spirit of
/// the PhamiJam P.
Path letter() {
  final stem = Path()
    ..moveTo(430, 380) // top of stem, under the spur
    ..quadraticBezierTo(470, 280, 530, 190) // horn at the top
    ..lineTo(530, 760)
    ..quadraticBezierTo(536, 792, 600, 800) // foot flick
    ..lineTo(560, 822)
    ..quadraticBezierTo(470, 850, 410, 905) // blade point at the bottom
    ..quadraticBezierTo(432, 840, 430, 760)
    ..close();

  final bowl = Path()
    ..moveTo(530, 318)
    ..cubicTo(650, 270, 790, 300, 800, 430)
    ..cubicTo(808, 545, 690, 620, 530, 610)
    ..lineTo(560, 570)
    ..cubicTo(668, 568, 720, 505, 712, 432)
    ..cubicTo(704, 355, 620, 340, 530, 372)
    ..close();

  final spur = Path()
    ..moveTo(300, 400)
    ..cubicTo(380, 405, 440, 350, 540, 325)
    ..lineTo(540, 350)
    ..cubicTo(470, 360, 440, 410, 430, 470)
    ..cubicTo(400, 440, 350, 420, 300, 400)
    ..close();

  return Path.combine(PathOperation.union, Path.combine(PathOperation.union, stem, bowl), spur);
}

void paintLetter(Canvas canvas, Path path) {
  final bounds = path.getBounds();

  // Extruded depth, like PhamiJam's bevelled gold.
  for (var i = 22; i > 0; i--) {
    canvas.drawPath(path.shift(Offset(i * 1.1, i * 1.5)), Paint()..color = Color.lerp(depth, const Color(0xFF5A0F35), i / 22)!);
  }

  // Neon metal face.
  canvas.drawPath(
    path,
    Paint()
      ..shader = ui.Gradient.linear(
        bounds.topLeft,
        bounds.bottomRight,
        metal,
        const [0.0, 0.25, 0.5, 0.72, 1.0],
      ),
  );

  // Sheen band across the face.
  canvas.save();
  canvas.clipPath(path);
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(bounds.left, bounds.top + bounds.height * 0.2),
        Offset(bounds.right, bounds.top + bounds.height * 0.55),
        [const Color(0x00FFFFFF), const Color(0x66FFFFFF), const Color(0x00FFFFFF)],
        const [0.3, 0.45, 0.6],
      ),
  );
  // Inner bevel: light top-left edge, dark bottom-right edge.
  canvas.drawPath(
    path.shift(const Offset(5, 6)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = const Color(0x40000000),
  );
  canvas.restore();
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = ui.Gradient.linear(
        bounds.topLeft,
        bounds.bottomRight,
        [const Color(0xFFFFF1D6), const Color(0x55FFFFFF), const Color(0x00FFFFFF)],
        const [0, 0.5, 1],
      ),
  );
}

void paintBackground(Canvas canvas) {
  final rect = Offset.zero & const Size(size, size);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, const [Color(0xFF1B0A2E), Color(0xFF07070D)]),
  );
  // Coloured glows behind the letter.
  canvas.drawCircle(const Offset(620, 380), 380, Paint()
    ..shader = ui.Gradient.radial(const Offset(620, 380), 380, const [Color(0x88FF2E4D), Color(0x00FF2E4D)]));
  canvas.drawCircle(const Offset(380, 720), 360, Paint()
    ..shader = ui.Gradient.radial(const Offset(380, 720), 360, const [Color(0x668B2CF5), Color(0x008B2CF5)]));
  // Faint crosshair ring: it's a tracker.
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6
    ..color = const Color(0x22FFFFFF);
  canvas.drawCircle(const Offset(512, 512), 360, ring);
  for (var i = 0; i < 4; i++) {
    final a = i * math.pi / 2;
    canvas.drawLine(
      Offset(512 + math.cos(a) * 330, 512 + math.sin(a) * 330),
      Offset(512 + math.cos(a) * 400, 512 + math.sin(a) * 400),
      ring,
    );
  }
}

Future<void> render(String path, {required bool background}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (background) paintBackground(canvas);
  // Centre the letter (plus its extrusion) and scale it into the icon's safe area.
  final shape = letter();
  final b = shape.getBounds();
  final scale = (background ? 600 : 640) / b.height;
  canvas.translate(size / 2, size / 2);
  canvas.scale(scale);
  canvas.translate(-b.center.dx - 10, -b.center.dy - 12);
  paintLetter(canvas, shape);
  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('generate logo', () async {
    Directory('assets/images').createSync(recursive: true);
    await render('assets/images/P.png', background: true);
    await render('assets/images/p-trans.png', background: false);
  });
}
