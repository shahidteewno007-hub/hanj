// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/widgets.dart';

void registerIframe(String videoId) {
  final viewType = 'youtube-iframe-$videoId';
  ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final iframe = html.IFrameElement()
      ..src =
          'https://www.youtube.com/embed/$videoId?autoplay=0&rel=0&modestbranding=1'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allowFullscreen = true
      ..setAttribute('allow',
          'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture');
    return iframe;
  });
}

Widget buildIframeView(String videoId) {
  return HtmlElementView(viewType: 'youtube-iframe-$videoId');
}
