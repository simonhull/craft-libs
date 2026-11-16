package dev.craft.kit.ui

import androidx.compose.runtime.Immutable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonObject

/** How a message reads: [Error] is tinted and stays longer. One this kit doesn't know is [Info]. */
enum class Tone(override val wire: String) : WireName {
    Info("info"),
    Error("error"),
}

/**
 * What the app is telling the user (wire kind 16, `ui::Status`): a [message] and a long job's
 * [progress]. A part this kit can't read is left out.
 */
@Immutable
data class Status(val message: Message? = null, val progress: Progress? = null) {
    /**
     * A message. [id] says which one it is (`Status::message_id`): a new id shows the same text again,
     * and the same id with new text (a countdown) updates the message on screen. 0 when the app doesn't say.
     */
    @Immutable
    data class Message(val text: String, val tone: Tone = Tone.Info, val id: Long = 0) {
        /** Which message this is on screen: its id when it has one, else its text and tone. */
        val identity: Any get() = if (id == 0L) text to tone else id

        /** How long it stays, in milliseconds: an error long enough to read twice. */
        val durationMillis: Long get() = if (tone == Tone.Error) 6_000 else 3_000
    }

    /** A job in progress; [fraction] 0..1, `null` while unknown; [cancel] the command that stops it, or `null`. */
    @Immutable
    data class Progress(val label: String, val fraction: Double? = null, val cancel: String? = null)

    companion object {
        /**
         * Wire kind 16 as JSON.
         *
         * @throws SerializationException when it isn't a JSON object.
         */
        fun parse(text: String): Status = with(parseObject(text)) {
            Status(
                message = part("message") { Message(string("text"), lenientEnum(string("tone"), Tone.Info), optCount("id") ?: 0) },
                progress = part("progress") { Progress(string("label"), optDouble("fraction"), optString("cancel")) },
            )
        }

        private inline fun <T> JsonObject.part(key: String, decode: JsonObject.() -> T): T? = try {
            (this[key] as? JsonObject)?.decode()
        } catch (_: SerializationException) {
            null
        }

        /** The message to show for [message]: none once that message was dismissed, whatever its text says since. */
        fun shown(message: Message?, dismissed: Any?): Message? = message?.takeUnless { it.identity == dismissed }
    }
}
