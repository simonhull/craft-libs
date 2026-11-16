package dev.craft.kit.ui

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

// Reading the app's JSON by hand: every node, row and menu entry decodes on its own, so one this
// kit can't read is skipped (or shown as a placeholder) and never takes its panel down with it.
// A required field that is missing or of the wrong type throws; the caller decides what that costs.

/** The JSON parser for everything the app sends. */
internal val wireJson = Json { ignoreUnknownKeys = true }

/** A field is missing or isn't what the wire format says. */
internal class WireException(message: String) : SerializationException(message)

internal fun parseObject(text: String): JsonObject =
    wireJson.parseToJsonElement(text) as? JsonObject ?: throw WireException("not an object")

internal fun JsonElement.asObject(): JsonObject = this as? JsonObject ?: throw WireException("not an object")

private fun JsonObject.present(key: String): JsonElement? = this[key]?.takeUnless { it is JsonNull }

internal fun JsonObject.string(key: String): String = optString(key) ?: throw WireException("`$key` is missing")

/** A string, or `null` when missing or `null`; another type throws. */
internal fun JsonObject.optString(key: String): String? = present(key)?.let {
    (it as? JsonPrimitive)?.takeIf(JsonPrimitive::isString)?.content ?: throw WireException("`$key` isn't text")
}

internal fun JsonObject.bool(key: String): Boolean = optBool(key) ?: throw WireException("`$key` is missing")

internal fun JsonObject.optBool(key: String): Boolean? = present(key)?.let {
    (it as? JsonPrimitive)?.takeUnless(JsonPrimitive::isString)?.booleanOrNull ?: throw WireException("`$key` isn't true or false")
}

internal fun JsonObject.double(key: String): Double = optDouble(key) ?: throw WireException("`$key` is missing")

internal fun JsonObject.optDouble(key: String): Double? = present(key)?.let {
    (it as? JsonPrimitive)?.takeUnless(JsonPrimitive::isString)?.doubleOrNull?.takeIf(Double::isFinite)
        ?: throw WireException("`$key` isn't a number")
}

/** A whole number from 0 up, as Rust's `u64` (up to `Long.MAX_VALUE`). */
internal fun JsonObject.count(key: String): Long = optCount(key) ?: throw WireException("`$key` is missing")

internal fun JsonObject.optCount(key: String): Long? = present(key)?.let {
    (it as? JsonPrimitive)?.takeUnless(JsonPrimitive::isString)?.longOrNull?.takeIf { n -> n >= 0 }
        ?: throw WireException("`$key` isn't a count")
}

internal fun JsonObject.array(key: String): JsonArray = optArray(key) ?: throw WireException("`$key` is missing")

internal fun JsonObject.optArray(key: String): JsonArray? = present(key)?.let { it as? JsonArray ?: throw WireException("`$key` isn't a list") }

/** Each element of [array] decoded by [decode]; one that throws is left out. */
internal inline fun <T> JsonArray.decodeEach(decode: (JsonElement) -> T): List<T> = mapNotNull { element ->
    try {
        decode(element)
    } catch (_: SerializationException) {
        null
    } catch (_: IllegalArgumentException) {
        null
    }
}

/** The enum constant whose wire name is [name], or [fallback] for one this kit doesn't know. */
internal inline fun <reified E> lenientEnum(name: String?, fallback: E): E where E : Enum<E>, E : WireName =
    enumValues<E>().firstOrNull { it.wire == name } ?: fallback

/** The enum constant whose wire name is [name]; one this kit doesn't know throws. */
internal inline fun <reified E> strictEnum(name: String): E where E : Enum<E>, E : WireName =
    enumValues<E>().firstOrNull { it.wire == name } ?: throw WireException("`$name` isn't known")

/** An enum as the wire spells it (`step_back`). */
interface WireName {
    val wire: String
}
