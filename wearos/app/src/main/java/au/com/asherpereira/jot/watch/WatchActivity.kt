package au.com.asherpereira.jot.watch

import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.*
import com.google.android.gms.wearable.*
import java.time.LocalDate
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

data class GlanceTask(val id: Int, val title: String, val meta: String)

class WatchActivity : ComponentActivity(), DataClient.OnDataChangedListener {
    private val data by lazy { Wearable.getDataClient(this) }
    private val prefs by lazy { getSharedPreferences("jot", MODE_PRIVATE) }
    private var tasks by mutableStateOf(emptyList<GlanceTask>())
    private var feedback by mutableStateOf("")
    private var saving by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        readSnapshot(prefs.getString("snapshot", "[]") ?: "[]")
        setContent {
            var text by rememberSaveable { mutableStateOf("") }
            MaterialTheme {
                ScalingLazyColumn(modifier = Modifier.fillMaxSize().background(Color.Black),
                    horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally) {
                    item { Text("Up next", style = MaterialTheme.typography.title2) }
                    if (tasks.isEmpty()) item { Text("No homework from your phone yet.") }
                    items(tasks, key = { it.id }) { task ->
                        Column {
                            Text(task.title, style = MaterialTheme.typography.title3)
                            Text(task.meta, style = MaterialTheme.typography.caption2)
                            Chip(label = { Text("Mark done") }, enabled = !saving, onClick = {
                                send(JSONObject().put("kind", "complete").put("taskId", task.id))
                            })
                        }
                    }
                    item { Text("Capture", style = MaterialTheme.typography.title3) }
                    item {
                        BasicTextField(value = text, onValueChange = { text = it.take(2000) },
                            modifier = Modifier.fillMaxWidth(.88f).background(Color.DarkGray).padding(10.dp),
                            textStyle = MaterialTheme.typography.body2.copy(color = Color.White),
                            cursorBrush = SolidColor(Color.White),
                            decorationBox = { inner -> Box { if (text.isEmpty()) Text("Homework"); inner() } })
                    }
                    item {
                        Chip(label = { Text("Save to phone") }, enabled = text.isNotBlank() && !saving, onClick = {
                            val captured = text.trim()
                            send(JSONObject().put("kind", "capture").put("text", captured)) {
                                if (text.trim() == captured) text = ""
                            }
                        })
                    }
                    if (feedback.isNotBlank()) item { Text(feedback, style = MaterialTheme.typography.caption2) }
                }
            }
        }
    }
    private fun readSnapshot(raw: String) {
        val decoded = runCatching {
            val rows = JSONArray(raw)
            List(rows.length()) { i -> rows.getJSONObject(i).let { GlanceTask(it.getInt("id"), it.getString("title"), it.getString("meta")) } }
        }.getOrNull() ?: return
        tasks = decoded
        prefs.edit().putString("snapshot", raw).apply()
    }
    private fun receive(item: DataItem) {
        if (item.uri.path == "/jot/snapshot") DataMapItem.fromDataItem(item).dataMap.getString("snapshot")?.let(::readSnapshot)
    }
    override fun onStart() {
        super.onStart()
        data.addListener(this)
        data.getDataItems(Uri.parse("wear://*/jot/snapshot")).addOnSuccessListener { buffer ->
            try { buffer.forEach(::receive) } finally { buffer.release() }
        }
    }
    override fun onStop() { data.removeListener(this); super.onStop() }
    override fun onDataChanged(events: DataEventBuffer) {
        events.filter { it.type == DataEvent.TYPE_CHANGED }.forEach { receive(it.dataItem) }
    }
    private fun send(action: JSONObject, saved: () -> Unit = {}) {
        if (saving) return
        saving = true
        val id = UUID.randomUUID().toString()
        action.put("id", id).put("localDate", LocalDate.now().toString())
        val request = PutDataMapRequest.create("/jot/action/$id")
        request.dataMap.putString("action", action.toString())
        data.putDataItem(request.asPutDataRequest().setUrgent()).addOnSuccessListener {
            saving = false; feedback = "Queued for phone"; saved()
        }.addOnFailureListener { saving = false; feedback = "Could not queue. Try again." }
    }
}
