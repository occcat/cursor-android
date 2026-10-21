import 'package:cursor_android/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Color expectedLightBackground = Color(0xFFF7F7F4);
const Color expectedDarkBackground = Color(0xFF14120B);
const Color expectedAccent = Color(0xFFF54E00);

/// WCAG AA minimum contrast for normal-size body text (SC 1.4.3).
const double bodyTextMinContrast = 4.5;

/// WCAG AA minimum contrast for graphical objects (SC 1.4.11).
const double graphicsMinContrast = 3.0;

/// WCAG 2.x contrast ratio, using Flutter's relative luminance.
double contrastRatio(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double lighter = la > lb ? la : lb;
  final double darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('palette constants match the specified warm-neutral values', () {
    expect(lightBackground, expectedLightBackground);
    expect(darkBackground, expectedDarkBackground);
    expect(accentColor, expectedAccent);
  });

  const List<(Brightness, Color)> cases = <(Brightness, Color)>[
    (Brightness.light, expectedLightBackground),
    (Brightness.dark, expectedDarkBackground),
  ];

  for (final (Brightness brightness, Color background) in cases) {
    group('${brightness.name} theme', () {
      test('uses the warm-neutral background and accent primary', () {
        final ThemeData theme = buildTheme(brightness);
        expect(theme.colorScheme.brightness, brightness);
        expect(theme.scaffoldBackgroundColor, background);
        expect(theme.colorScheme.surface, background);
        expect(theme.colorScheme.primary, expectedAccent);
      });

      test('onSurface body text meets WCAG AA 4.5:1', () {
        final ColorScheme scheme = buildTheme(brightness).colorScheme;
        expect(
          contrastRatio(scheme.onSurface, background),
          greaterThanOrEqualTo(bodyTextMinContrast),
        );
      });

      test('accent graphics meet WCAG non-text 3:1', () {
        final ColorScheme scheme = buildTheme(brightness).colorScheme;
        expect(
          contrastRatio(scheme.primary, background),
          greaterThanOrEqualTo(graphicsMinContrast),
        );
      });
    });
  }
}
