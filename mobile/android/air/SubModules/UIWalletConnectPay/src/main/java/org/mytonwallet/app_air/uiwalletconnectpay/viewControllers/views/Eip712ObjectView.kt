package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.views

import android.annotation.SuppressLint
import android.content.Context
import android.text.method.LinkMovementMethod
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.MSignDataPayload.SignDataPayloadEip712.TypeField

@SuppressLint("ViewConstructor")
class Eip712ObjectView(
    context: Context,
    obj: Map<String, Any?>,
    typeName: String,
    types: Map<String, List<TypeField>>,
) : LinearLayout(context), WThemedView {

    companion object {
        private const val MAX_DEPTH = 32
        private const val INDENT_STEP = 10
        private const val MAX_INDENT_LEVEL = 4
    }

    private val scalarLabels = mutableListOf<WLabel>()
    private val nameLabels = mutableListOf<WLabel>()

    init {
        orientation = VERTICAL
        addView(valueView(obj, typeName, types, depth = 0))
        updateTheme()
    }

    override fun updateTheme() {
        scalarLabels.forEach { it.setTextColor(WColor.PrimaryText.color) }
        nameLabels.forEach { it.setTextColor(WColor.SecondaryText.color) }
    }

    private fun valueView(
        value: Any?,
        solidityType: String?,
        types: Map<String, List<TypeField>>,
        depth: Int,
    ): LinearLayout {
        if (depth > MAX_DEPTH) {
            return scalarView(scalarText(value))
        }
        val elementType = solidityType?.let { arrayElementType(it) }
        if (elementType != null) {
            return arrayView(value as? List<*> ?: emptyList<Any?>(), elementType, types, depth)
        }
        val fields = solidityType?.let { types[it] }

        @Suppress("UNCHECKED_CAST")
        val dict = value as? Map<String, Any?>
        if (!fields.isNullOrEmpty() && dict != null) {
            return structView(dict, fields, types, depth)
        }
        if (solidityType != null && isPrimitiveType(solidityType)) {
            return scalarView(scalarText(value))
        }
        if (value != null) {
            return unknownValueView(value, types, depth)
        }
        return scalarView("")
    }

    private fun structView(
        obj: Map<String, Any?>,
        fields: List<TypeField>,
        types: Map<String, List<TypeField>>,
        depth: Int,
    ): LinearLayout {
        val container = verticalContainer()
        applyIndent(container, depth)
        fields.forEachIndexed { index, field ->
            addSpaced(
                container,
                fieldRow(field.name, valueView(obj[field.name], field.type, types, depth + 1)),
                topMargin = if (index == 0) 0 else 10
            )
        }
        return container
    }

    private fun unknownValueView(
        value: Any,
        types: Map<String, List<TypeField>>,
        depth: Int,
    ): LinearLayout {
        @Suppress("UNCHECKED_CAST")
        when (value) {
            is Map<*, *> -> {
                val obj = value as Map<String, Any?>
                val container = verticalContainer()
                applyIndent(container, depth)
                obj.keys.sorted().forEachIndexed { index, key ->
                    addSpaced(
                        container,
                        fieldRow(key, valueView(obj[key], null, types, depth + 1)),
                        topMargin = if (index == 0) 0 else 10
                    )
                }
                return container
            }

            is List<*> -> return arrayView(value, null, types, depth)
            else -> return scalarView(scalarText(value))
        }
    }

    private fun arrayView(
        values: List<*>,
        elementType: String?,
        types: Map<String, List<TypeField>>,
        depth: Int,
    ): LinearLayout {
        val container = verticalContainer()
        values.forEachIndexed { index, element ->
            val row = LinearLayout(context).apply {
                orientation = HORIZONTAL
                layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            }
            row.addView(
                nameLabel("[$index]").apply {
                    layoutParams = LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                        marginEnd = 6.dp
                    }
                }
            )
            row.addView(
                valueView(element, elementType, types, depth + 1).apply {
                    layoutParams = LayoutParams(0, WRAP_CONTENT, 1f)
                }
            )
            addSpaced(container, row, topMargin = if (index == 0) 0 else 8)
        }
        return container
    }

    private fun fieldRow(name: String, content: LinearLayout): LinearLayout {
        val row = verticalContainer()
        addSpaced(
            row,
            nameLabel(name).apply { layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT) },
            topMargin = 0
        )
        addSpaced(row, content, topMargin = 4)
        return row
    }

    private fun scalarView(text: String): LinearLayout {
        val container = LinearLayout(context).apply {
            orientation = VERTICAL
            layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        }
        val label = WLabel(context).apply {
            setStyle(16f, WFont.Medium)
            setLineHeight(20f)
            gravity = Gravity.START
            setTextIsSelectable(true)
            movementMethod = LinkMovementMethod.getInstance()
            this.text = text
            layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        }
        scalarLabels.add(label)
        label.setTextColor(WColor.PrimaryText.color)
        container.addView(label)
        return container
    }

    private fun nameLabel(text: String) = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        this.text = text
        nameLabels.add(this)
        setTextColor(WColor.SecondaryText.color)
    }

    private fun verticalContainer() = LinearLayout(context).apply {
        orientation = VERTICAL
        layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT)
    }

    private fun addSpaced(container: LinearLayout, child: android.view.View, topMargin: Int) {
        val lp = (child.layoutParams as? LayoutParams)
            ?: LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        lp.topMargin = topMargin.dp
        child.layoutParams = lp
        container.addView(child)
    }

    private fun applyIndent(container: LinearLayout, depth: Int) {
        val indent = minOf(depth, MAX_INDENT_LEVEL) * INDENT_STEP
        container.setPadding(indent.dp, 0, 0, 0)
    }

    private fun scalarText(value: Any?): String = when (value) {
        null -> ""
        is String -> value
        is Boolean -> value.toString()
        is Double -> doubleText(value)
        is Number -> value.toString()
        is Map<*, *> -> prettyJson(value)
        is List<*> -> prettyJson(value)
        else -> value.toString()
    }

    private fun doubleText(value: Double): String {
        if (!value.isFinite()) return value.toString()
        val decimal = java.math.BigDecimal(value)
        return if (decimal.stripTrailingZeros().scale() <= 0) {
            decimal.toBigInteger().toString()
        } else {
            value.toString()
        }
    }

    private fun prettyJson(value: Any?): String = try {
        when (value) {
            is Map<*, *> -> JSONObject(value.entries.associate { (k, v) -> k.toString() to v })
                .toString(2)

            is List<*> -> JSONArray(value).toString(2)
            else -> JSONObject.wrap(value)?.toString() ?: value.toString()
        }
    } catch (_: Throwable) {
        value.toString()
    }

    private fun arrayElementType(type: String): String? {
        if (!type.endsWith("]")) return null
        val open = type.lastIndexOf('[')
        if (open == -1) return null
        val count = type.substring(open + 1, type.length - 1)
        if (count.isNotEmpty() && !count.all { it.isDigit() }) return null
        return type.substring(0, open)
    }

    private fun isPrimitiveType(type: String): Boolean {
        if (type == "bytes" || type == "string" || type == "address" || type == "bool") {
            return true
        }
        if (type.startsWith("bytes")) return isFixedBytesSuffixValid(type.substring(5))
        if (type.startsWith("uint")) return isIntegerSuffixValid(type.substring(4))
        if (type.startsWith("int")) return isIntegerSuffixValid(type.substring(3))
        return false
    }

    private fun isIntegerSuffixValid(suffix: String): Boolean {
        if (suffix.isEmpty()) return true // bare uint/int (min = 0)
        if (!suffix.all { it.isDigit() }) return false
        val value = suffix.toIntOrNull() ?: return false
        return value in 0..999
    }

    private fun isFixedBytesSuffixValid(suffix: String): Boolean {
        if (suffix.isEmpty() || !suffix.all { it.isDigit() } || suffix.first() == '0') return false
        val value = suffix.toIntOrNull() ?: return false
        return value in 1..32
    }
}
