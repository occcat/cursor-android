/// Usage pool brand colors, from Kotlin 0.1.5 `CursorTheme.kt`.
///
/// Graphics only (markers, bars): they are tuned for at least 3:1 contrast,
/// not for body text.
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
