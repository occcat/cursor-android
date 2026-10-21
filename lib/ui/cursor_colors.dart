/// Brand, pool and status colors, from Kotlin 0.1.5 `CursorTheme.kt`.
///
/// Pool colors and [cursorAccent] are for graphics only (markers, bars,
/// dots): they are tuned for at least 3:1 contrast, not for body text.
library;

import 'package:flutter/widgets.dart';

/// Cursor (auto) pool, the same in light and dark themes.
const Color poolCursor = Color(0xFFF54E00);

/// Other (API) pool on the light background.
const Color poolOtherLight = Color(0xFF82817C);

/// Other (API) pool on the dark background.
const Color poolOtherDark = Color(0xFF767470);

/// Cursor pool color for [brightness].
Color poolCursorColor(Brightness brightness) => poolCursor;

/// Other pool color for [brightness].
Color poolOtherColor(Brightness brightness) =>
    brightness == Brightness.dark ? poolOtherDark : poolOtherLight;

/// Brand accent (Kotlin `accent`), the same in light and dark themes.
const Color cursorAccent = Color(0xFFF54E00);

/// Success on the light background (Kotlin `success`).
const Color successLight = Color(0xFF17775A);

/// Success on the dark background (Kotlin `success`).
const Color successDark = Color(0xFF3FB68B);

/// Error on the light background (Kotlin `error`).
const Color errorLight = Color(0xFFB8244A);

/// Error on the dark background (Kotlin `error`).
const Color errorDark = Color(0xFFE5506F);

/// Secondary text on the light background (Kotlin `textSecondary`).
const Color textSecondaryLight = Color(0xFF676660);

/// Secondary text on the dark background (Kotlin `textSecondary`).
const Color textSecondaryDark = Color(0xFF969592);

/// Tertiary text on the light background (Kotlin `textTertiary`).
const Color textTertiaryLight = Color(0xFFA3A39E);

/// Tertiary text on the dark background (Kotlin `textTertiary`).
const Color textTertiaryDark = Color(0xFF6B6965);

/// Success color for [brightness].
Color successColor(Brightness brightness) =>
    brightness == Brightness.dark ? successDark : successLight;

/// Error color for [brightness].
Color errorColor(Brightness brightness) =>
    brightness == Brightness.dark ? errorDark : errorLight;

/// Secondary text color for [brightness].
Color textSecondaryColor(Brightness brightness) =>
    brightness == Brightness.dark ? textSecondaryDark : textSecondaryLight;

/// Tertiary text color for [brightness].
Color textTertiaryColor(Brightness brightness) =>
    brightness == Brightness.dark ? textTertiaryDark : textTertiaryLight;
