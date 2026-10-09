package app.cursor.android

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import app.cursor.android.ui.CursorColors
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CursorThemeTest {
    private val palettes = mapOf("light" to CursorColors.light, "dark" to CursorColors.dark)

    @Test
    fun primaryTextKeepsEnhancedContrastOnSurfaces() {
        palettes.forEach { (theme, colors) ->
            listOf(colors.bg, colors.card, colors.card03).forEach {
                assertContrast(theme, "fg", colors.fg, it, 7.0)
            }
        }
    }

    @Test
    fun secondaryTextMeetsAaOnSurfaces() {
        palettes.forEach { (theme, colors) ->
            listOf(colors.bg, colors.card, colors.card03).forEach {
                assertContrast(theme, "textSecondary", colors.textSecondary, it, 4.5)
            }
        }
    }

    @Test
    fun coloredTextMeetsAaOnPageAndCards() {
        palettes.forEach { (theme, colors) ->
            listOf(colors.bg, colors.card).forEach { surface ->
                assertContrast(theme, "accentText", colors.accentText, surface, 4.5)
                assertContrast(theme, "error", colors.error, surface, 4.5)
                assertContrast(theme, "success", colors.success, surface, 4.5)
            }
        }
    }

    @Test
    fun graphicsMeetNonTextContrast() {
        palettes.forEach { (theme, colors) ->
            listOf(colors.bg, colors.card).forEach { surface ->
                assertContrast(theme, "poolCursor", colors.poolCursor, surface, 3.0)
                assertContrast(theme, "poolOther", colors.poolOther, surface, 3.0)
                assertContrast(theme, "accent", colors.accent, surface, 3.0)
            }
        }
    }

    @Test
    fun resourceColorsMatchComposePalette() {
        val tokens: Map<String, (CursorColors) -> Color> =
            mapOf(
                "cursor_bg" to CursorColors::bg,
                "cursor_fg" to CursorColors::fg,
                "cursor_card" to CursorColors::card,
                "cursor_text_secondary" to CursorColors::textSecondary,
                "cursor_border02" to CursorColors::border02,
                "cursor_accent" to CursorColors::accent,
                "cursor_launcher_background" to { _: CursorColors -> CursorColors.dark.bg },
            )
        listOf("values" to CursorColors.light, "values-night" to CursorColors.dark).forEach {
            (folder, colors) ->
            val nodes =
                DocumentBuilderFactory.newInstance()
                    .newDocumentBuilder()
                    .parse(File("src/main/res/$folder/colors.xml"))
                    .getElementsByTagName("color")
            assertTrue("$folder has no colors", nodes.length > 0)
            for (index in 0 until nodes.length) {
                val node = nodes.item(index)
                val name = node.attributes.getNamedItem("name").nodeValue
                val token = checkNotNull(tokens[name]) { "$folder/$name has no Compose token" }
                assertEquals("$folder/$name", hex(token(colors)), node.textContent.trim())
            }
        }
    }

    private fun assertContrast(theme: String, name: String, fg: Color, bg: Color, min: Double) {
        val ratio = contrast(fg, bg)
        assertTrue("$theme $name on ${hex(bg)} is $ratio, below $min", ratio >= min)
    }

    private fun contrast(first: Color, second: Color): Double {
        val lighter = maxOf(first.luminance(), second.luminance())
        val darker = minOf(first.luminance(), second.luminance())
        return (lighter + 0.05) / (darker + 0.05)
    }

    private fun hex(color: Color): String = "#%06X".format(color.toArgb() and 0xFFFFFF)
}
