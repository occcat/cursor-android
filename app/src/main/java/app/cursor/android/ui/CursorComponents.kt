package app.cursor.android.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp

/** Color changes on chips, switches and buttons use cursor.com's short ease-out. */
@Composable
private fun animatedColor(target: Color, label: String): Color {
    val color by
        animateColorAsState(
            target,
            tween(CursorMotion.fastMillis, easing = CursorMotion.easeOut),
            label = label,
        )
    return color
}

/** Primary pill: ink fill with page-colored text, softening to [CursorColors.fgPressed]. */
@Composable
fun CursorButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    val colors = CursorTheme.colors
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val container =
        animatedColor(
            when {
                !enabled -> colors.card03
                pressed -> colors.fgPressed
                else -> colors.fg
            },
            "primaryContainer",
        )
    Button(
        onClick = onClick,
        modifier = modifier.heightIn(min = 48.dp),
        enabled = enabled,
        colors =
            ButtonDefaults.buttonColors(
                containerColor = container,
                contentColor = colors.bg,
                disabledContainerColor = container,
                disabledContentColor = colors.textTertiary,
            ),
        elevation = null,
        border = BorderStroke(1.dp, container),
        interactionSource = interaction,
        content = content,
    )
}

/** Secondary pill on the raised card tone; replaces outlined buttons. */
@Composable
fun CursorSecondaryButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    val colors = CursorTheme.colors
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val container = animatedColor(if (pressed) colors.card04 else colors.card03, "secondary")
    Button(
        onClick = onClick,
        modifier = modifier.heightIn(min = 48.dp),
        enabled = enabled,
        colors =
            ButtonDefaults.buttonColors(
                containerColor = container,
                contentColor = colors.fg,
                disabledContainerColor = colors.card,
                disabledContentColor = colors.textTertiary,
            ),
        elevation = null,
        border = BorderStroke(1.dp, colors.border01),
        interactionSource = interaction,
        content = content,
    )
}

/** Text color roles for borderless buttons. */
enum class CursorTone {
    Default,
    Link,
    Danger,
}

/** Borderless button; [CursorTone.Link] marks external links, [CursorTone.Danger] removals. */
@Composable
fun CursorTextButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    tone: CursorTone = CursorTone.Default,
    contentPadding: PaddingValues = ButtonDefaults.TextButtonContentPadding,
    content: @Composable RowScope.() -> Unit,
) {
    val colors = CursorTheme.colors
    TextButton(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        contentPadding = contentPadding,
        colors =
            ButtonDefaults.textButtonColors(
                contentColor =
                    when (tone) {
                        CursorTone.Default -> colors.fg
                        CursorTone.Link -> colors.accentText
                        CursorTone.Danger -> colors.error
                    },
                disabledContentColor = colors.textTertiary,
            ),
        content = content,
    )
}

/** Flat card separated by tone rather than shadow; clickable cards darken while pressed. */
@Composable
fun CursorCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = CursorTheme.colors
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val cardColors =
        CardDefaults.cardColors(
            containerColor = animatedColor(if (pressed) colors.card02 else colors.card, "card"),
            contentColor = colors.fg,
        )
    val elevation =
        CardDefaults.cardElevation(
            defaultElevation = 0.dp,
            pressedElevation = 0.dp,
            focusedElevation = 0.dp,
            hoveredElevation = 0.dp,
            draggedElevation = 0.dp,
            disabledElevation = 0.dp,
        )
    if (onClick == null) {
        Card(modifier, MaterialTheme.shapes.medium, cardColors, elevation, content = content)
    } else {
        Card(
            onClick = onClick,
            modifier = modifier,
            shape = MaterialTheme.shapes.medium,
            colors = cardColors,
            elevation = elevation,
            interactionSource = interaction,
            content = content,
        )
    }
}

/** Selectable chip: hairline outline when idle, ink fill when selected. */
@Composable
fun CursorChip(selected: Boolean, onClick: () -> Unit, label: String) {
    val colors = CursorTheme.colors
    val container = animatedColor(if (selected) colors.fg else colors.fg.copy(alpha = 0f), "chip")
    val text = animatedColor(if (selected) colors.bg else colors.fg, "chipLabel")
    val edge = animatedColor(if (selected) colors.fg else colors.border025, "chipBorder")
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label, style = MaterialTheme.typography.labelMedium) },
        shape = MaterialTheme.shapes.small,
        colors =
            FilterChipDefaults.filterChipColors(
                containerColor = container,
                labelColor = text,
                selectedContainerColor = container,
                selectedLabelColor = text,
            ),
        border =
            FilterChipDefaults.filterChipBorder(
                enabled = true,
                selected = selected,
                borderColor = edge,
                selectedBorderColor = edge,
                borderWidth = 1.dp,
                selectedBorderWidth = 1.dp,
            ),
    )
}

/** Action chip sharing the idle look of [CursorChip]. */
@Composable
fun CursorActionChip(onClick: () -> Unit, label: String) {
    val colors = CursorTheme.colors
    AssistChip(
        onClick = onClick,
        label = { Text(label, style = MaterialTheme.typography.labelMedium) },
        shape = MaterialTheme.shapes.small,
        colors =
            AssistChipDefaults.assistChipColors(
                containerColor = Color.Transparent,
                labelColor = colors.fg,
            ),
        border =
            AssistChipDefaults.assistChipBorder(enabled = true, borderColor = colors.border025),
    )
}

/** Outlined field with an 8 dp radius, hairline idle edge and darker focus edge. */
@Composable
fun CursorTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    label: @Composable (() -> Unit)? = null,
    supportingText: @Composable (() -> Unit)? = null,
    isError: Boolean = false,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    singleLine: Boolean = false,
    minLines: Int = 1,
) {
    val colors = CursorTheme.colors
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier,
        enabled = enabled,
        label = label,
        supportingText = supportingText,
        isError = isError,
        visualTransformation = visualTransformation,
        keyboardOptions = keyboardOptions,
        singleLine = singleLine,
        minLines = minLines,
        shape = MaterialTheme.shapes.medium,
        colors =
            OutlinedTextFieldDefaults.colors(
                focusedTextColor = colors.fg,
                unfocusedTextColor = colors.fg,
                focusedContainerColor = Color.Transparent,
                unfocusedContainerColor = Color.Transparent,
                disabledContainerColor = Color.Transparent,
                errorContainerColor = Color.Transparent,
                cursorColor = colors.fg,
                errorCursorColor = colors.error,
                focusedBorderColor = colors.border03,
                unfocusedBorderColor = colors.border02,
                disabledBorderColor = colors.border01,
                errorBorderColor = colors.error,
                focusedLabelColor = colors.textSecondary,
                unfocusedLabelColor = colors.textSecondary,
                errorLabelColor = colors.error,
                focusedSupportingTextColor = colors.textSecondary,
                unfocusedSupportingTextColor = colors.textSecondary,
                errorSupportingTextColor = colors.error,
            ),
    )
}

/**
 * Switch with an ink track when on. The idle thumb uses `border03` rather than the plan's
 * tertiary text tone so the off state keeps 3:1 against its track.
 */
@Composable
fun CursorSwitch(checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    val colors = CursorTheme.colors
    val track = animatedColor(if (checked) colors.fg else colors.card03, "switchTrack")
    val thumb = animatedColor(if (checked) colors.bg else colors.border03, "switchThumb")
    val edge = animatedColor(if (checked) colors.fg else colors.border025, "switchBorder")
    Switch(
        checked = checked,
        onCheckedChange = onCheckedChange,
        colors =
            SwitchDefaults.colors(
                checkedThumbColor = thumb,
                checkedTrackColor = track,
                checkedBorderColor = edge,
                uncheckedThumbColor = thumb,
                uncheckedTrackColor = track,
                uncheckedBorderColor = edge,
            ),
    )
}

/** 6 dp pool bar on the shared track; value changes ease in with the slow spring curve. */
@Composable
fun CursorProgress(progress: Float, color: Color, modifier: Modifier = Modifier) {
    val value by
        animateFloatAsState(
            progress,
            tween(CursorMotion.slowMillis, easing = CursorMotion.spring),
            label = "progress",
        )
    LinearProgressIndicator(
        progress = { value },
        modifier = modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)),
        color = color,
        trackColor = CursorTheme.colors.track,
        strokeCap = StrokeCap.Round,
        gapSize = 0.dp,
        drawStopIndicator = {},
    )
}

/** Small filled circle used for agent states and usage pools. */
@Composable
fun Dot(color: Color, modifier: Modifier = Modifier) {
    Box(modifier.size(6.dp).background(color, CircleShape))
}

/** Maps API status strings to a dot color; the string itself is always shown verbatim. */
@Composable
fun AgentStatus(status: String, modifier: Modifier = Modifier) {
    val colors = CursorTheme.colors
    val tint =
        when (status) {
            "RUNNING",
            "CREATING" -> colors.accent
            "FINISHED" -> colors.success
            "ERROR",
            "FAILED",
            "EXPIRED" -> colors.error
            "ARCHIVED" -> colors.textTertiary
            else -> colors.poolOther
        }
    Row(
        modifier,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Dot(tint)
        Text(status, style = MaterialTheme.typography.labelSmall)
    }
}

/** Secondary 14 sp copy beneath headings and controls. */
@Composable
fun Description(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        modifier,
        style = MaterialTheme.typography.bodyMedium,
        color = CursorTheme.colors.textSecondary,
    )
}

/** Secondary 12 sp footnote. */
@Composable
fun Note(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        modifier,
        style = MaterialTheme.typography.bodySmall,
        color = CursorTheme.colors.textSecondary,
    )
}

/** Alert dialog on the card tone with a 12 dp radius and no tonal tint. */
@Composable
fun CursorAlertDialog(
    onDismissRequest: () -> Unit,
    confirmButton: @Composable () -> Unit,
    dismissButton: @Composable (() -> Unit)? = null,
    title: @Composable (() -> Unit)? = null,
    text: @Composable (() -> Unit)? = null,
) {
    val colors = CursorTheme.colors
    AlertDialog(
        onDismissRequest = onDismissRequest,
        confirmButton = confirmButton,
        dismissButton = dismissButton,
        title =
            title?.let { slot -> { ProvideTextStyle(MaterialTheme.typography.titleLarge, slot) } },
        text = text,
        shape = MaterialTheme.shapes.large,
        containerColor = colors.card,
        titleContentColor = colors.fg,
        textContentColor = colors.textSecondary,
        tonalElevation = 0.dp,
    )
}
