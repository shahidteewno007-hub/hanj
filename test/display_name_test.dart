// DisplayName holds the same limits as firestore.rules' hanjNameOk (code
// batch 2, LR-014). The names here are the ones firestore-tests/names.test.js
// sends to the rules, so the app and the server agree on each.
import 'package:flutter_test/flutter_test.dart';
import 'package:hanj/core/display_name.dart';

void main() {
  test('24 characters pass, 25 do not, counted as the rules count', () {
    expect(DisplayName.problem('abcdefghijklmnopqrstuvwx'), isNull);
    expect(DisplayName.problem('abcdefghijklmnopqrstuvwxy'), isNotNull);
    expect(DisplayName.problem('é' * 24), isNull);
  });

  test('kept words are refused as words of their own', () {
    for (final name in ['Hanj', 'hanj team', 'The Hanj Team', 'Admin',
        'admin_01', 'Moderator', 'mod', 'Hanj Support', 'OFFICIAL', 'staff']) {
      expect(DisplayName.isReserved(name), isTrue, reason: name);
    }
  });

  test('a kept word inside another word is fine', () {
    for (final name in ['Hanjiro', 'Badminton fan', 'modern_otaku',
        'Supporter', 'naruto_fan99']) {
      expect(DisplayName.problem(name), isNull, reason: name);
    }
  });

  test('usable() cuts to 24, trims, and drops empty or kept names', () {
    expect(DisplayName.usable('  Shahid  '), 'Shahid');
    expect(DisplayName.usable('A name from before the limits, far too long'),
        'A name from before the l');
    expect(DisplayName.usable(''), isNull);
    expect(DisplayName.usable(null), isNull);
    expect(DisplayName.usable('Hanj Team'), isNull);
    // Cut by code point, so an emoji is never split in half.
    final cut = DisplayName.usable('😀' * 30)!;
    expect(cut.runes.length, 24);
  });
}
