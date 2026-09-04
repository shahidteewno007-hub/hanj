// Mobile implementation
import 'dart:typed_data';
import 'package:gal/gal.dart';

Future<void> saveImageToGallery(List<int> bytes, String name) async {
  await Gal.putImageBytes(Uint8List.fromList(bytes), name: name);
}
