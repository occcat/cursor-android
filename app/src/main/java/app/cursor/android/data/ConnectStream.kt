package app.cursor.android.data

/** One Connect frame: flag byte, four-byte big-endian length, then payload. */
data class ConnectFrame(val flags: Int, val payload: ByteArray) {
    val end: Boolean
        get() = flags and 0x02 != 0
}

data class ConversationUpdate(val offsetKey: String?, val text: String, val end: Boolean = false)

internal fun encodeConversationRequest(bcId: String, offsetKey: String?): ByteArray {
    var body = encodeStringField(1, bcId)
    if (!offsetKey.isNullOrBlank()) body += encodeStringField(2, offsetKey)
    return body
}

internal fun interactionFrame(offset: String, text: String): ByteArray {
    val update = encodeStringField(1, text)
    val wrapped = encodeStringField(1, offset) + encodeMessageField(2, update)
    return envelope(0, encodeMessageField(4, wrapped))
}

internal fun endFrame(json: String = "{}"): ByteArray =
    envelope(2, json.toByteArray(Charsets.UTF_8))

internal fun envelope(flags: Int, payload: ByteArray): ByteArray {
    val length = payload.size
    return byteArrayOf(
        flags.toByte(),
        (length ushr 24).toByte(),
        (length ushr 16).toByte(),
        (length ushr 8).toByte(),
        length.toByte(),
    ) + payload
}

internal fun decodeConversationPayload(payload: ByteArray): ConversationUpdate {
    val top = parseProto(payload)
    if (top.any { it.field == 14 }) return ConversationUpdate(null, "")
    val interaction =
        top.firstOrNull { it.field == 4 }?.bytes ?: return ConversationUpdate(null, "")
    val inner = parseProto(interaction)
    val offset = inner.firstOrNull { it.field == 1 }?.bytes?.let(::utf8Text)
    val update = inner.firstOrNull { it.field == 2 }?.bytes
    return ConversationUpdate(offset, if (update == null) "" else collectText(update))
}

private fun collectText(message: ByteArray): String {
    val parts = mutableListOf<String>()
    fun walk(bytes: ByteArray) {
        val fields = parseProto(bytes)
        if (fields.isEmpty()) return
        for (field in fields) {
            val raw = field.bytes ?: continue
            val text = utf8Text(raw)
            if (text != null) {
                if (!text.matches(Regex("[0-9a-fA-F]{32,}"))) parts += text
            } else {
                walk(raw)
            }
        }
    }
    walk(message)
    return parts.joinToString("")
}

private data class ProtoField(val field: Int, val bytes: ByteArray?)

private fun parseProto(data: ByteArray): List<ProtoField> {
    val out = mutableListOf<ProtoField>()
    var index = 0
    while (index < data.size) {
        val key = readVarint(data, index) ?: return emptyList()
        index = key.second
        val field = (key.first ushr 3).toInt()
        when ((key.first and 7).toInt()) {
            0 -> {
                val value = readVarint(data, index) ?: return emptyList()
                index = value.second
                out += ProtoField(field, null)
            }
            1 -> {
                if (index + 8 > data.size) return emptyList()
                index += 8
                out += ProtoField(field, null)
            }
            2 -> {
                val length = readVarint(data, index) ?: return emptyList()
                index = length.second
                val size = length.first.toInt()
                if (size < 0 || index + size > data.size) return emptyList()
                out += ProtoField(field, data.copyOfRange(index, index + size))
                index += size
            }
            5 -> {
                if (index + 4 > data.size) return emptyList()
                index += 4
                out += ProtoField(field, null)
            }
            else -> return emptyList()
        }
    }
    return out
}

private fun readVarint(data: ByteArray, start: Int): Pair<Long, Int>? {
    var value = 0L
    var shift = 0
    var index = start
    while (index < data.size && shift < 64) {
        val byte = data[index].toInt() and 0xFF
        value = value or ((byte and 0x7F).toLong() shl shift)
        index++
        if (byte and 0x80 == 0) return value to index
        shift += 7
    }
    return null
}

private fun encodeStringField(field: Int, value: String): ByteArray {
    val bytes = value.toByteArray(Charsets.UTF_8)
    return encodeVarint((field shl 3) or 2) + encodeVarint(bytes.size) + bytes
}

private fun encodeMessageField(field: Int, message: ByteArray): ByteArray =
    encodeVarint((field shl 3) or 2) + encodeVarint(message.size) + message

private fun encodeVarint(value: Int): ByteArray {
    val out = mutableListOf<Byte>()
    var rest = value
    while (rest > 0x7F) {
        out += ((rest and 0x7F) or 0x80).toByte()
        rest = rest ushr 7
    }
    out += rest.toByte()
    return out.toByteArray()
}

private fun utf8Text(bytes: ByteArray): String? {
    if (bytes.isEmpty()) return null
    val text = runCatching { bytes.toString(Charsets.UTF_8) }.getOrNull() ?: return null
    if ('\uFFFD' in text) return null
    if (text.any { it.code < 32 && it != '\n' && it != '\r' && it != '\t' }) return null
    return text
}
