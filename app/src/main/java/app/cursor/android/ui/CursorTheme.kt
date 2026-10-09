package app.cursor.android.ui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/**
 * Warm neutral palette shared by the app, widgets, overlay and website.
 *
 * Text roles are tuned for WCAG AA on [bg], [card] and [card03]; [accent] and the pool colors are
 * for graphics only (at least 3:1). Use [accentText] for orange text. `border025` mirrors the
 * website's `--border-02-5`.
 */
@Immutable
data class CursorColors(
    val bg: Color,
    val fg: Color,
    val fgPressed: Color,
    val card: Color,
    val card01: Color,
    val card02: Color,
    val card03: Color,
    val card04: Color,
    val cardWarm: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val border01: Color,
    val border02: Color,
    val border025: Color,
    val border03: Color,
    val accent: Color,
    val accentText: Color,
    val success: Color,
    val error: Color,
    val warning: Color,
    val poolCursor: Color,
    val poolOther: Color,
) {
    /** Progress track behind both usage pools. */
    val track: Color
        get() = card03

    companion object {
        val light =
            CursorColors(
                bg = Color(0xFFF7F7F4),
                fg = Color(0xFF26251E),
                fgPressed = Color(0xFF3B3A33),
                card = Color(0xFFF2F1ED),
                card01 = Color(0xFFF0EFEB),
                card02 = Color(0xFFEBEAE5),
                card03 = Color(0xFFE6E5E0),
                card04 = Color(0xFFE1E0DB),
                cardWarm = Color(0xFFF3EDE6),
                textSecondary = Color(0xFF676660),
                textTertiary = Color(0xFFA3A39E),
                border01 = Color(0xFFEDECE9),
                border02 = Color(0xFFE2E2DF),
                border025 = Color(0xFFCDCDC9),
                border03 = Color(0xFF7A7974),
                accent = Color(0xFFF54E00),
                accentText = Color(0xFFC43E00),
                success = Color(0xFF17775A),
                error = Color(0xFFB8244A),
                warning = Color(0xFFA46700),
                poolCursor = Color(0xFFF54E00),
                poolOther = Color(0xFF82817C),
            )

        val dark =
            CursorColors(
                bg = Color(0xFF14120B),
                fg = Color(0xFFEDECEC),
                fgPressed = Color(0xFFD7D6D5),
                card = Color(0xFF1B1913),
                card01 = Color(0xFF1D1B15),
                card02 = Color(0xFF201E18),
                card03 = Color(0xFF26241E),
                card04 = Color(0xFF2B2923),
                cardWarm = Color(0xFF1C1713),
                textSecondary = Color(0xFF969592),
                textTertiary = Color(0xFF6B6965),
                border01 = Color(0xFF1F1D16),
                border02 = Color(0xFF2A2822),
                border025 = Color(0xFF3F3E38),
                border03 = Color(0xFF969592),
                accent = Color(0xFFF54E00),
                accentText = Color(0xFFF54E00),
                success = Color(0xFF3FB68B),
                error = Color(0xFFE5506F),
                warning = Color(0xFFF1B467),
                poolCursor = Color(0xFFF54E00),
                poolOther = Color(0xFF767470),
            )
    }
}

/** Defaults to the light palette so previews and tests without [CursorTheme] still render. */
val LocalCursorColors = staticCompositionLocalOf { CursorColors.light }

/** Durations and easings borrowed from cursor.com's interaction timing. */
object CursorMotion {
    const val fastMillis = 140
    const val slowMillis = 250
    val spring: Easing = CubicBezierEasing(0.25f, 1f, 0.5f, 1f)
    val easeOut: Easing = CubicBezierEasing(0f, 0f, 0.2f, 1f)
}

/** Accessors for Cursor tokens that Material 3 has no role for. */
object CursorTheme {
    val colors: CursorColors
        @Composable @ReadOnlyComposable get() = LocalCursorColors.current
}

/** Follows the system light or dark setting; there is no in-app theme switch. */
@Composable
fun CursorTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (dark) CursorColors.dark else CursorColors.light
    CompositionLocalProvider(LocalCursorColors provides colors) {
        MaterialTheme(
            colorScheme = cursorColorScheme(colors, dark),
            typography = cursorTypography,
            shapes = cursorShapes,
            content = content,
        )
    }
}

private fun cursorColorScheme(colors: CursorColors, dark: Boolean): ColorScheme =
    (if (dark) darkColorScheme() else lightColorScheme()).copy(
        primary = colors.fg,
        onPrimary = colors.bg,
        primaryContainer = colors.card03,
        onPrimaryContainer = colors.fg,
        secondary = colors.fg,
        onSecondary = colors.bg,
        secondaryContainer = colors.card03,
        onSecondaryContainer = colors.fg,
        tertiary = colors.accent,
        onTertiary = Color.White,
        background = colors.bg,
        onBackground = colors.fg,
        surface = colors.bg,
        onSurface = colors.fg,
        surfaceVariant = colors.card02,
        onSurfaceVariant = colors.textSecondary,
        surfaceTint = colors.bg,
        inverseSurface = colors.fg,
        inverseOnSurface = colors.bg,
        error = colors.error,
        onError = Color.White,
        errorContainer = colors.cardWarm,
        onErrorContainer = colors.error,
        outline = colors.border025,
        outlineVariant = colors.border02,
        surfaceContainerLowest = colors.bg,
        surfaceContainerLow = colors.card,
        surfaceContainer = colors.card01,
        surfaceContainerHigh = colors.card02,
        surfaceContainerHighest = colors.card03,
    )

/** Regular weights and slightly negative tracking on headings, using system fonts only. */
private val cursorTypography =
    Typography().run {
        Typography(
            headlineLarge =
                headlineLarge.copy(
                    fontSize = 26.sp,
                    lineHeight = 32.5.sp,
                    fontWeight = FontWeight.Normal,
                    letterSpacing = (-0.0125).em,
                ),
            headlineMedium =
                headlineMedium.copy(
                    fontSize = 22.sp,
                    lineHeight = 28.6.sp,
                    fontWeight = FontWeight.Normal,
                    letterSpacing = (-0.005).em,
                ),
            headlineSmall =
                headlineSmall.copy(
                    fontSize = 20.sp,
                    lineHeight = 26.sp,
                    fontWeight = FontWeight.Normal,
                    letterSpacing = (-0.005).em,
                ),
            titleLarge =
                titleLarge.copy(
                    fontSize = 18.sp,
                    lineHeight = 25.sp,
                    fontWeight = FontWeight.Normal,
                    letterSpacing = 0.em,
                ),
            titleMedium =
                titleMedium.copy(
                    fontSize = 16.sp,
                    lineHeight = 24.sp,
                    fontWeight = FontWeight.Medium,
                    letterSpacing = 0.005.em,
                ),
            titleSmall =
                titleSmall.copy(
                    fontSize = 14.sp,
                    lineHeight = 20.sp,
                    fontWeight = FontWeight.Medium,
                    letterSpacing = 0.em,
                ),
            bodyLarge =
                bodyLarge.copy(
                    fontSize = 16.sp,
                    lineHeight = 24.sp,
                    fontWeight = FontWeight.Normal,
                    letterSpacing = 0.005.em,
                ),
            bodyMedium =
                bodyMedium.copy(
                    fontSize = 14.sp,
                    lineHeight = 21.sp,
                    fontWeight = FontWeight.Normal,
                    letterSpacing = 0.01.em,
                ),
            bodySmall =
                bodySmall.copy(
                    fontSize = 12.sp,
                    lineHeight = 18.sp,
                    fontWeight = FontWeight.Normal,
                    letterSpacing = 0.01.em,
                ),
            labelLarge =
                labelLarge.copy(
                    fontSize = 14.sp,
                    lineHeight = 20.sp,
                    fontWeight = FontWeight.Normal,
                    letterSpacing = 0.005.em,
                ),
            labelMedium =
                labelMedium.copy(
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                    fontWeight = FontWeight.Medium,
                    letterSpacing = 0.01.em,
                ),
            labelSmall =
                labelSmall.copy(
                    fontSize = 11.sp,
                    lineHeight = 16.sp,
                    fontWeight = FontWeight.Normal,
                    letterSpacing = 0.04.em,
                    fontFamily = FontFamily.Monospace,
                ),
        )
    }

private val cursorShapes =
    Shapes(
        extraSmall = RoundedCornerShape(4.dp),
        small = RoundedCornerShape(6.dp),
        medium = RoundedCornerShape(8.dp),
        large = RoundedCornerShape(12.dp),
        extraLarge = RoundedCornerShape(16.dp),
    )
