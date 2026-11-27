package au.com.asherpereira.jot

import android.net.Uri
import com.google.android.gms.wearable.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), DataClient.OnDataChangedListener {
    private lateinit var channel: MethodChannel
    private val data by lazy { Wearable.getDataClient(this) }
    private val actionPrefix = "/jot/action/"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jot/watch")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pending" -> data.getDataItems(Uri.parse("wear://*$actionPrefix"), DataClient.FILTER_PREFIX)
                    .addOnSuccessListener { buffer ->
                        try {
                            val inbox = mutableMapOf<String, String?>()
                            for (item in buffer) {
                                val id = item.uri.lastPathSegment ?: continue
                                inbox[id] = DataMapItem.fromDataItem(item).dataMap.getString("action")
                            }
                            result.success(inbox)
                        } finally { buffer.release() }
                    }.addOnFailureListener { result.error("wear_unavailable", "Watch unavailable", null) }
                "ack" -> {
                    val id = call.arguments as String
                    data.deleteDataItems(Uri.parse("wear://*$actionPrefix").buildUpon().appendPath(id).build())
                        .addOnSuccessListener { result.success(null) }
                        .addOnFailureListener { result.error("wear_unavailable", "Watch unavailable", null) }
                }
                "publish" -> {
                    val request = PutDataMapRequest.create("/jot/snapshot")
                    request.dataMap.putString("snapshot", call.arguments as String)
                    data.putDataItem(request.asPutDataRequest().setUrgent())
                        .addOnSuccessListener { result.success(null) }
                        .addOnFailureListener { result.error("wear_unavailable", "Watch unavailable", null) }
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onStart() { super.onStart(); data.addListener(this) }
    override fun onStop() { data.removeListener(this); super.onStop() }
    override fun onDataChanged(events: DataEventBuffer) {
        if (events.any { it.type == DataEvent.TYPE_CHANGED && it.dataItem.uri.path?.startsWith(actionPrefix) == true }
            && ::channel.isInitialized) channel.invokeMethod("changed", null)
    }
}
