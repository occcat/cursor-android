package app.cursor.android.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.cursor.android.ui.label

@Composable
fun WidgetPicker() {
    val context = LocalContext.current
    val manager = AppWidgetManager.getInstance(context)
    val fallback = label("Long-press your home screen and choose Widgets.", "长按桌面并选择小组件。")
    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        listOf(
                UsageWidgetReceiver::class.java to label("Add Usage", "添加用量"),
                AgentsWidgetReceiver::class.java to label("Add Agents", "添加会话"),
                ActionsWidgetReceiver::class.java to label("Add Actions", "添加操作"),
            )
            .forEach { (receiver, title) ->
                OutlinedButton(
                    onClick = {
                        if (
                            !manager.isRequestPinAppWidgetSupported ||
                                !manager.requestPinAppWidget(
                                    ComponentName(context, receiver),
                                    null,
                                    null,
                                )
                        ) {
                            Toast.makeText(context, fallback, Toast.LENGTH_LONG).show()
                        }
                    }
                ) {
                    Text(title)
                }
            }
    }
}
