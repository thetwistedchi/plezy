import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/player_style.dart';

void main() {
  test('the Retrowave theme carries the Retrowave player style', () {
    expect(monoThemeUncached(MonoPalette.retrowave).extension<PlayerStyle>(), PlayerStyle.retrowave);
  });

  test('other themes keep the stock white player', () {
    for (final palette in [MonoPalette.dark, MonoPalette.light, MonoPalette.oled]) {
      expect(monoThemeUncached(palette).extension<PlayerStyle>(), isNull);
    }
  });

  testWidgets('PlayerStyle.of falls back to stock', (tester) async {
    late PlayerStyle style;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            style = PlayerStyle.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(style.playButtonFill, isNull);
    expect(style.progress, isNull);
  });
}
