package app.cursor.android

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** A debug-only host for real Glance RemoteViews; never shipped in release builds. */
class WidgetQaActivity : Activity() {
    lateinit var content: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        content =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(24, 100, 24, 60)
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
