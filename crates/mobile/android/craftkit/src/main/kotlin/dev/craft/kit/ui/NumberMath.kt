package dev.craft.kit.ui

import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.ParsePosition
import java.util.Locale
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToLong

/**
 * A number control's arithmetic: the slider moves through positions 0..1, spread over the range by
 * the scale; values (shown, typed, sent) are in the number's own units.
 */
object NumberMath {
    /** [v] snapped to a multiple of [step] (as the app's `Number::step` means it) and kept in [range]. */
    fun snap(v: Double, step: Double?, range: ClosedFloatingPointRange<Double>): Double {
        val snapped = step?.takeIf { it.isFinite() && it > 0 }?.let { (v / it).roundToLong() * it } ?: v
        return snapped.coerceIn(range.start, range.endInclusive)
    }

    /**
     * Where [v] sits on the slider, 0..1. On a log scale `v = min·(max/min)^t`; a range a log scale
     * can't spread (`min <= 0`) is linear; an empty range is 0.
     */
    fun position(v: Double, range: ClosedFloatingPointRange<Double>, scale: Scale): Double {
        val (lo, hi) = range.start to range.endInclusive
        if (hi <= lo) return 0.0
        val t = if (isLog(scale, range)) ln(v / lo) / ln(hi / lo) else (v - lo) / (hi - lo)
        return if (t.isFinite()) t.coerceIn(0.0, 1.0) else 0.0
    }

    /** The value at slider position [t] (kept in 0..1), before any step snaps it: the inverse of [position]. */
    fun valueAt(t: Double, range: ClosedFloatingPointRange<Double>, scale: Scale): Double {
        val (lo, hi) = range.start to range.endInclusive
        val at = (if (t.isFinite()) t else 0.0).coerceIn(0.0, 1.0)
        val v = if (isLog(scale, range)) lo * (hi / lo).pow(at) else lo + at * (hi - lo)
        return v.coerceIn(lo, maxOf(lo, hi))
    }

    private fun isLog(scale: Scale, range: ClosedFloatingPointRange<Double>) = scale == Scale.Log && range.start > 0

    /** The value as shown, in [locale], never grouped (so it can fill the typing field and parse back). */
    fun format(v: Double, unit: NumberUnit, withUnit: Boolean = true, locale: Locale = Locale.getDefault()): String {
        fun number(x: Double, maxDigits: Int) = DecimalFormat("0", DecimalFormatSymbols.getInstance(locale)).apply {
            maximumFractionDigits = maxDigits
            isGroupingUsed = false
        }.format(x + 0.0) // + 0.0: never "-0"
        return when (unit) {
            NumberUnit.Percent -> number(v * 100, 0) + if (withUnit) " %" else ""
            NumberUnit.Pixels -> number(v, 1) + if (withUnit) " px" else ""
            NumberUnit.Degrees -> number(v, 0) + if (withUnit) "°" else ""
            NumberUnit.None -> number(v, 2)
        }
    }

    /**
     * A typed value: read strictly in [locale] (no grouping), else as a plain `1234.5`, ignoring a
     * typed unit; a percentage becomes 0..1. `null` for anything else ("50abc", or "0,5" where a comma
     * only groups), rather than a guess the user didn't mean.
     */
    fun parse(text: String, unit: NumberUnit, locale: Locale = Locale.getDefault()): Double? {
        val bare = listOf("%", "px", "°").fold(text) { acc, suffix -> acc.replace(suffix, "") }.trim()
        if (bare.isEmpty()) return null
        val n = (strict(bare, locale) ?: bare.toDoubleOrNull())?.takeIf(Double::isFinite) ?: return null
        return if (unit == NumberUnit.Percent) n / 100 else n
    }

    private fun strict(text: String, locale: Locale): Double? {
        val format = DecimalFormat("0", DecimalFormatSymbols.getInstance(locale)).apply { isGroupingUsed = false }
        val at = ParsePosition(0)
        val n = format.parse(text, at) ?: return null
        return n.toDouble().takeIf { at.index == text.length }
    }
}
