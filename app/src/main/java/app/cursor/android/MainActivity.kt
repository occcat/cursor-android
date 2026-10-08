package app.cursor.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.cursor.android.ui.CursorApp
import app.cursor.android.ui.CursorViewModel
import app.cursor.android.widget.WidgetDestination
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : AppCompatActivity() {
    private val widgetDestination = mutableStateOf<WidgetDestination?>(null)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        widgetDestination.value = WidgetDestination.from(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        widgetDestination.value = WidgetDestination.from(intent)
        setContent {
            val model: CursorViewModel = viewModel()
            val state by model.uiState.collectAsStateWithLifecycle()
            CursorApp(state, model, widgetDestination.value) { widgetDestination.value = null }
        }
    }
}
