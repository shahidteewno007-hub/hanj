import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';

/// A cover's own colour, read from the cover (Print Room, DESIGN.md §9), for
/// the places that have no `coverImage.color`: list entries keep only the
/// cover's URL, so Home and Profile ask here.
///
/// The cover is decoded 16 px wide from the same URL the screen shows. On
/// the phone CachedNetworkImage shares one download per URL, so this makes
/// no request of its own, and nothing is stored but the colour, in memory.
/// Its most prominent colour wins, not the average (which turns every busy
/// cover brown): pixels vote by hue, weighted by saturation times brightness,
/// and the heaviest hue, with its two neighbours, gives its mean. A grey or
/// nearly grey cover gives null, and so does anything that goes wrong, so
/// the field simply stays sumi. It never throws: Crashlytics reports an
/// unhandled async error as fatal (CLAUDE.md).
///
/// Colours are kept by key, most recently used last, up to [_maxEntries].
class HankoCoverColour {
  HankoCoverColour._();

  static const int _width = 16;
  static const int _bins = 24;
  static const int _maxEntries = 300;
  static const Duration _timeout = Duration(seconds: 20);

  // Map literals keep insertion order, so the first key is the least
  // recently used.
  static final Map<Object, Color?> _known = <Object, Color?>{};
  static final Map<Object, Future<Color?>> _reading = <Object, Future<Color?>>{};

  /// Whether a colour (or the lack of one) is already known for [key].
  static bool knows(Object key) => _known.containsKey(key);

  /// The colour already known for [key], without reading anything. Null when
  /// the cover has none, or hasn't been read yet (see [knows]).
  static Color? peek(Object key) => _known[key];

  /// The colour of the cover at [url].
  static Future<Color?> ofUrl(String url) =>
      of(CachedNetworkImageProvider(url), key: url);

  /// The colour of any image. [key] identifies it in the memory cache.
  static Future<Color?> of(ImageProvider provider, {required Object key}) {
    if (_known.containsKey(key)) {
      final colour = _known.remove(key);
      _known[key] = colour; // now the most recently used
      return Future<Color?>.value(colour);
    }
    final reading = _reading[key];
    if (reading != null) return reading;
    final future = _read(provider).then((colour) {
      _reading.remove(key);
      _known[key] = colour;
      while (_known.length > _maxEntries) {
        _known.remove(_known.keys.first);
      }
      return colour;
    });
    _reading[key] = future;
    return future;
  }

  static Future<Color?> _read(ImageProvider provider) async {
    ui.Image? image;
    try {
      image = await _decode(provider);
      if (image == null) return null;
      final data =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (data == null) return null;
      return _prominent(data);
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
    }
  }

  static Future<ui.Image?> _decode(ImageProvider provider) {
    final completer = Completer<ui.Image?>();
    final stream = ResizeImage(provider, width: _width)
        .resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    void finish(ui.Image? image) {
      if (completer.isCompleted) {
        image?.dispose();
      } else {
        completer.complete(image);
      }
      stream.removeListener(listener);
    }

    listener = ImageStreamListener(
      (info, _) {
        finish(info.image.clone());
        info.dispose();
      },
      onError: (_, _) => finish(null),
    );
    stream.addListener(listener);
    return completer.future.timeout(_timeout, onTimeout: () {
      stream.removeListener(listener);
      return null;
    });
  }

  static Color? _prominent(ByteData data) {
    final weight = List<double>.filled(_bins, 0);
    final red = List<double>.filled(_bins, 0);
    final green = List<double>.filled(_bins, 0);
    final blue = List<double>.filled(_bins, 0);
    var pixels = 0;
    var voted = 0.0;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      if (data.getUint8(i + 3) < 128) continue; // transparent: no vote
      pixels++;
      final r = data.getUint8(i);
      final g = data.getUint8(i + 1);
      final b = data.getUint8(i + 2);
      final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
      final vote = hsv.saturation * hsv.value;
      if (vote < 0.08) continue; // greys, blacks and whites don't vote
      final bin = (hsv.hue / 360 * _bins).floor() % _bins;
      weight[bin] += vote;
      red[bin] += r * vote;
      green[bin] += g * vote;
      blue[bin] += b * vote;
      voted += vote;
    }
    // A cover with almost no colour in it keeps the page's sumi.
    if (pixels == 0 || voted < 0.04 * pixels) return null;
    var best = 0;
    var bestWeight = -1.0;
    for (var k = 0; k < _bins; k++) {
      final around =
          weight[k] + weight[(k + 1) % _bins] + weight[(k + _bins - 1) % _bins];
      if (around > bestWeight) {
        bestWeight = around;
        best = k;
      }
    }
    var sumWeight = 0.0;
    var sumRed = 0.0;
    var sumGreen = 0.0;
    var sumBlue = 0.0;
    for (final k in [(best + _bins - 1) % _bins, best, (best + 1) % _bins]) {
      sumWeight += weight[k];
      sumRed += red[k];
      sumGreen += green[k];
      sumBlue += blue[k];
    }
    if (sumWeight <= 0) return null;
    return Color.fromARGB(255, (sumRed / sumWeight).round(),
        (sumGreen / sumWeight).round(), (sumBlue / sumWeight).round());
  }
}
