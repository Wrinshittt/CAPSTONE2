// lib/utils/pano_normalizer.dart
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Ensures a 2:1 equirect-like JPEG with FULL WIDTH filled by real pixels.
/// - Always covers horizontally: no left/right padding or blur bands.
/// - Only crops or pads vertically (top/bottom).
/// - 'blur' mode builds a blurred BACKDROP only for top/bottom if needed.
class PanoNormalizer {
  static Future<Uint8List> fetchAsEquirect(
    String url, {
    String mode = 'solid', // 'solid' or 'blur'
    int jpegQuality = 92,
    int bgColor = 0xFF0A3D62, // ARGB for 'solid' mode
  }) async {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
      throw Exception('Fetch failed: ${resp.statusCode}');
    }

    final decoded = img.decodeImage(resp.bodyBytes);
    if (decoded == null) {
      throw Exception('Cannot decode image');
    }

    final src0 = img.bakeOrientation(decoded);
    final w0 = src0.width;
    final h0 = src0.height;
    final ratio = w0 / h0;

    // If already ~2:1, just re-encode.
    if ((ratio - 2.0).abs() < 0.01) {
      return Uint8List.fromList(img.encodeJpg(src0, quality: jpegQuality));
    }

    // Target canvas: keep width = source width (avoid softening),
    // height = width / 2 (strict 2:1).
    final outW = w0;
    final outH = outW ~/ 2;

    // --- Step 1: COVER horizontally by scaling width to outW ---
    final baseByWidth = img.copyResize(src0, width: outW);
    // Now baseByWidth.height may be > outH (tall) or < outH (short).

    img.Image canvas;

    if (baseByWidth.height >= outH) {
      // --- Step 2A: too tall -> center CROP vertically to outH ---
      final cropY = ((baseByWidth.height - outH) / 2).round();
      final cropped = img.copyCrop(
        baseByWidth,
        x: 0,
        y: cropY,
        width: outW,
        height: outH,
      );
      canvas = cropped;
    } else {
      // --- Step 2B: too short -> PAD top/bottom to reach outH ---
      // Build a background canvas (blur or solid), then center the image.
      if (mode == 'blur') {
        // Make a vertical cover backdrop from the same image (after width-fit).
        // Scale to COVER vertically
        final coverScale = outH / baseByWidth.height;
        final coverH = (baseByWidth.height * coverScale).round();
        var cover = img.copyResize(baseByWidth, width: outW, height: coverH);
        // center-crop to outH
        final cropY2 = ((cover.height - outH) / 2).round().clamp(
          0,
          coverH - outH,
        );
        cover = img.copyCrop(cover, x: 0, y: cropY2, width: outW, height: outH);
        // blur backdrop
        cover = img.gaussianBlur(cover, radius: 16);
        canvas = cover;
      } else {
        final a = (bgColor >> 24) & 0xFF;
        final r = (bgColor >> 16) & 0xFF;
        final g = (bgColor >> 8) & 0xFF;
        final b = (bgColor) & 0xFF;
        final color = img.ColorRgba8(r, g, b, a);
        canvas = img.Image(
          width: outW,
          height: outH,
          numChannels: 4,
          backgroundColor: color,
        );
      }

      final dy = ((outH - baseByWidth.height) / 2).round();
      img.compositeImage(canvas, baseByWidth, dstX: 0, dstY: dy);
    }

    return Uint8List.fromList(img.encodeJpg(canvas, quality: jpegQuality));
  }
}
