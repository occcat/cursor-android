package app.cursor.android

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Hosts real Glance RemoteViews without horizontal insets, so a 320 dp widget fits a 320 dp screen.
 * This test surface is absent from release builds.
 */
class WidgetQaActivity : Activity() {
    lateinit var content: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        content =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(0, 24, 0, 24)
                setBackgroundColor(Color.rgb(220, 218, 211))
            }
        setContentView(ScrollView(this).apply { addView(content) })
    }

    fun heading(text: String) {
        content.addView(
            TextView(this).apply {
                this.text = text
                textSize = 14f
                setTextColor(Color.BLACK)
                setPadding(0, 24, 0, 16)
            }
        )
    }
}
