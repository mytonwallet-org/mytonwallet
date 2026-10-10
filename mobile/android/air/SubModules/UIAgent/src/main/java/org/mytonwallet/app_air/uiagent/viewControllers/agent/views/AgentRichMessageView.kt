package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.GridLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import androidx.core.view.ViewCompat
import kotlin.math.abs
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.helpers.spans.ExtraHitLinkMovementMethod
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

private const val MAX_RENDERED_TABLE_ROWS = 200
private const val MAX_RENDERED_TABLE_CELLS = 1_000

internal fun limitTableForRendering(table: MarkdownParser.Block.Table): MarkdownParser.Block.Table {
    val retainedRows = mutableListOf<List<MarkdownParser.TableCell>>()
    var remainingCells = MAX_RENDERED_TABLE_CELLS
    for (row in table.rows.take(MAX_RENDERED_TABLE_ROWS)) {
        if (remainingCells == 0) break
        val retainedRow = row.take(remainingCells)
        retainedRows.add(retainedRow)
        remainingCells -= retainedRow.size
    }

    val isTruncated = retainedRows.size < table.rows.size ||
        retainedRows.indices.any { retainedRows[it].size < table.rows[it].size }
    if (!isTruncated) return table

    val clampedRows = retainedRows.mapIndexed { rowIndex, row ->
        row.map { cell ->
            cell.copy(rowSpan = minOf(cell.rowSpan, retainedRows.size - rowIndex))
        }
    }
    val retainedTable = table.copy(rows = clampedRows)
    val columnCount = MarkdownParser.resolveTableGrid(retainedTable).columnCount.coerceAtLeast(1)
    val truncationRow = listOf(
        MarkdownParser.TableCell(
            text = "…",
            alignment = MarkdownParser.TableAlignment.CENTER,
            columnSpan = columnCount
        )
    )
    return retainedTable.copy(rows = clampedRows + listOf(truncationRow))
}

@SuppressLint("ViewConstructor")
class AgentRichMessageView(context: Context) : LinearLayout(context) {

    private var maximumContentWidth = 0

    init {
        orientation = VERTICAL
        setPaddingDpLocalized(20, 10, 14, 10)
    }

    fun configure(
        blocks: List<MarkdownParser.Block>,
        maximumContentWidth: Int,
        codeColor: Int,
        onUrlClick: ((String) -> Unit)?,
        detectsUrls: Boolean,
        onLongClickListener: OnLongClickListener
    ) {
        this.maximumContentWidth = maximumContentWidth
        removeAllViews()

        blocks.forEachIndexed { index, block ->
            val child = when (block) {
                is MarkdownParser.Block.Text -> createTextView(
                    block.value,
                    maximumContentWidth,
                    codeColor,
                    onUrlClick,
                    detectsUrls,
                    onLongClickListener
                )

                is MarkdownParser.Block.Table -> AgentTableBlockView(context).apply {
                    configure(
                        block,
                        maximumContentWidth,
                        codeColor,
                        onUrlClick,
                        detectsUrls,
                        onLongClickListener
                    )
                }
            }
            addView(
                child,
                LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    if (index > 0) topMargin = 8.dp
                }
            )
        }
    }

    private fun createTextView(
        value: String,
        maximumContentWidth: Int,
        codeColor: Int,
        onUrlClick: ((String) -> Unit)?,
        detectsUrls: Boolean,
        onLongClickListener: OnLongClickListener
    ) = WLabel(context).apply {
        setStyle(adaptiveFontSize())
        setTextColor(WColor.PrimaryText.color)
        isSingleLine = false
        maxLines = Int.MAX_VALUE
        ellipsize = null
        maxWidth = maximumContentWidth
        useCustomEmoji = true
        movementMethod = ExtraHitLinkMovementMethod(2.dp, 2.dp)
        text =
            MarkdownParser.parse(
                value,
                codeColor,
                null,
                onUrlClick,
                detectsUrls,
                textSize = textSize
            )
        setOnLongClickListener(onLongClickListener)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val maximumWidth = maximumContentWidth + paddingLeft + paddingRight
        val constrainedWidthSpec = if (maximumWidth > 0) {
            val availableWidth = when (MeasureSpec.getMode(widthMeasureSpec)) {
                MeasureSpec.UNSPECIFIED -> maximumWidth
                else -> minOf(MeasureSpec.getSize(widthMeasureSpec), maximumWidth)
            }
            MeasureSpec.makeMeasureSpec(
                availableWidth,
                MeasureSpec.AT_MOST
            )
        } else {
            widthMeasureSpec
        }
        super.onMeasure(constrainedWidthSpec, heightMeasureSpec)
    }
}

@SuppressLint("ViewConstructor")
private class AgentTableBlockView(context: Context) : LinearLayout(context) {

    init {
        orientation = VERTICAL
    }

    fun configure(
        table: MarkdownParser.Block.Table,
        maximumWidth: Int,
        codeColor: Int,
        onUrlClick: ((String) -> Unit)?,
        detectsUrls: Boolean,
        onLongClickListener: OnLongClickListener
    ) {
        removeAllViews()
        table.title?.takeIf { it.isNotBlank() }?.let { title ->
            addView(
                WLabel(context).apply {
                    setStyle(adaptiveFontSize(), WFont.Medium)
                    setTextColor(WColor.PrimaryText.color)
                    isSingleLine = false
                    maxLines = Int.MAX_VALUE
                    maxWidth = maximumWidth
                    useCustomEmoji = true
                    movementMethod = ExtraHitLinkMovementMethod(2.dp, 2.dp)
                    text =
                        MarkdownParser.parse(
                            title,
                            codeColor,
                            null,
                            onUrlClick,
                            detectsUrls,
                            textSize = textSize
                        )
                    setOnLongClickListener(onLongClickListener)
                    ViewCompat.setAccessibilityHeading(this, true)
                },
                LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    bottomMargin = 6.dp
                }
            )
        }
        addView(
            AgentTableView(context).apply {
                configure(
                    table,
                    maximumWidth,
                    codeColor,
                    onUrlClick,
                    detectsUrls,
                    onLongClickListener
                )
            },
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )
    }
}

@SuppressLint("ViewConstructor")
private class AgentTableView(context: Context) : HorizontalScrollView(context) {

    private val tableLayout = AgentTableLayout(context)
    private var maximumWidth = 0
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var handlesOverflowGesture = false
    private var horizontalDragStarted = false

    init {
        isHorizontalScrollBarEnabled = false
        isHorizontalFadingEdgeEnabled = true
        setFadingEdgeLength(12.dp)
        isFillViewport = false
        overScrollMode = OVER_SCROLL_IF_CONTENT_SCROLLS
        addView(tableLayout, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
    }

    fun configure(
        table: MarkdownParser.Block.Table,
        maximumWidth: Int,
        codeColor: Int,
        onUrlClick: ((String) -> Unit)?,
        detectsUrls: Boolean,
        onLongClickListener: OnLongClickListener
    ) {
        this.maximumWidth = maximumWidth
        tableLayout.configure(table, codeColor, onUrlClick, detectsUrls, onLongClickListener)
        setOnLongClickListener(onLongClickListener)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                horizontalDragStarted = false
                handlesOverflowGesture = canScrollHorizontally(-1) || canScrollHorizontally(1)
                if (handlesOverflowGesture) parent?.requestDisallowInterceptTouchEvent(true)
            }

            MotionEvent.ACTION_MOVE -> {
                if (handlesOverflowGesture && !horizontalDragStarted) {
                    val dx = abs(event.x - downX)
                    val dy = abs(event.y - downY)
                    if (dx > touchSlop && dx >= dy) {
                        horizontalDragStarted = true
                    } else if (dy > touchSlop && dy > dx) {
                        handlesOverflowGesture = false
                        parent?.requestDisallowInterceptTouchEvent(false)
                    }
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                handlesOverflowGesture = false
                parent?.requestDisallowInterceptTouchEvent(false)
            }
        }
        return super.dispatchTouchEvent(event)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val constrainedWidthSpec = if (maximumWidth > 0) {
            val availableWidth = when (MeasureSpec.getMode(widthMeasureSpec)) {
                MeasureSpec.UNSPECIFIED -> maximumWidth
                else -> minOf(MeasureSpec.getSize(widthMeasureSpec), maximumWidth)
            }
            MeasureSpec.makeMeasureSpec(availableWidth, MeasureSpec.AT_MOST)
        } else {
            widthMeasureSpec
        }
        super.onMeasure(constrainedWidthSpec, heightMeasureSpec)
    }

    override fun getSolidColor(): Int = WColor.SecondaryBackground.color
}

private class AgentTableLayout(context: Context) : GridLayout(context) {

    private data class CellView(val view: WLabel, val placement: MarkdownParser.PlacedTableCell)

    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = if (ThemeManager.isDark) 0xFF3A3A3D.toInt() else 0x333C3C43
        style = Paint.Style.STROKE
        strokeWidth = 1f
    }
    private val headerPaint = Paint().apply {
        color = WColor.PrimaryText.color.colorWithAlpha(14)
    }
    private val stripePaint = Paint().apply {
        color = WColor.PrimaryText.color.colorWithAlpha(7)
    }
    private val cellViews = mutableListOf<CellView>()
    private var bordered = true
    private var striped = false

    init {
        orientation = HORIZONTAL
        alignmentMode = ALIGN_BOUNDS
        isColumnOrderPreserved = true
        isRowOrderPreserved = true
        clipToOutline = true
    }

    fun configure(
        table: MarkdownParser.Block.Table,
        codeColor: Int,
        onUrlClick: ((String) -> Unit)?,
        detectsUrls: Boolean,
        onLongClickListener: OnLongClickListener
    ) {
        removeAllViews()
        cellViews.clear()
        bordered = table.bordered
        striped = table.striped
        background = GradientDrawable().apply {
            setColor(Color.TRANSPARENT)
            cornerRadius = 8f.dp
        }

        val grid = MarkdownParser.resolveTableGrid(limitTableForRendering(table))
        columnCount = grid.columnCount.coerceAtLeast(1)
        rowCount = grid.rowCount.coerceAtLeast(1)
        grid.cells.forEach { placement ->
            val cell = placement.cell
            val label = WLabel(context).apply {
                setStyle(
                    adaptiveFontSize(),
                    if (cell.header) WFont.Medium else WFont.Regular
                )
                setTextColor(WColor.PrimaryText.color)
                isSingleLine = false
                maxLines = Int.MAX_VALUE
                ellipsize = null
                minimumWidth = 72.dp * cell.columnSpan
                maxWidth = 220.dp * cell.columnSpan
                gravity = verticalGravity(cell.verticalAlignment) or
                    horizontalGravity(cell.alignment)
                setPadding(10.dp, 8.dp, 10.dp, 8.dp)
                useCustomEmoji = true
                movementMethod = ExtraHitLinkMovementMethod(2.dp, 2.dp)
                text =
                    if (cell.isPlainText) {
                        cell.text
                    } else {
                        MarkdownParser.parse(
                            cell.text,
                            codeColor,
                            null,
                            onUrlClick,
                            detectsUrls,
                            textSize = textSize
                        )
                    }
                setOnLongClickListener(onLongClickListener)
                ViewCompat.setAccessibilityHeading(this, cell.header)
            }
            val layoutParams = LayoutParams(
                spec(placement.row, cell.rowSpan, FILL),
                spec(placement.column, cell.columnSpan, FILL)
            ).apply {
                width = WRAP_CONTENT
                height = WRAP_CONTENT
            }
            addView(label, layoutParams)
            cellViews.add(CellView(label, placement))
        }
    }

    override fun dispatchDraw(canvas: Canvas) {
        cellViews.forEach { cellView ->
            val view = cellView.view
            val cell = cellView.placement.cell
            val backgroundPaint = when {
                cell.header -> headerPaint
                striped && cellView.placement.row % 2 == 1 -> stripePaint
                else -> null
            }
            if (backgroundPaint != null) {
                canvas.drawRect(
                    view.left.toFloat(),
                    view.top.toFloat(),
                    view.right.toFloat(),
                    view.bottom.toFloat(),
                    backgroundPaint
                )
            }
        }

        super.dispatchDraw(canvas)

        if (!bordered) return
        cellViews.forEach { cellView ->
            val view = cellView.view
            if (view.left > 0) {
                canvas.drawLine(
                    view.left.toFloat(),
                    view.top.toFloat(),
                    view.left.toFloat(),
                    view.bottom.toFloat(),
                    linePaint
                )
            }
            if (view.top > 0) {
                canvas.drawLine(
                    view.left.toFloat(),
                    view.top.toFloat(),
                    view.right.toFloat(),
                    view.top.toFloat(),
                    linePaint
                )
            }
        }
        val halfStroke = linePaint.strokeWidth / 2f
        canvas.drawRoundRect(
            halfStroke,
            halfStroke,
            width - halfStroke,
            height - halfStroke,
            8f.dp,
            8f.dp,
            linePaint
        )
    }

    private fun horizontalGravity(alignment: MarkdownParser.TableAlignment): Int = when (
        alignment
    ) {
        MarkdownParser.TableAlignment.START -> Gravity.START
        MarkdownParser.TableAlignment.CENTER -> Gravity.CENTER_HORIZONTAL
        MarkdownParser.TableAlignment.END -> Gravity.END
    }

    private fun verticalGravity(alignment: MarkdownParser.TableVerticalAlignment): Int = when (
        alignment
    ) {
        MarkdownParser.TableVerticalAlignment.TOP -> Gravity.TOP
        MarkdownParser.TableVerticalAlignment.MIDDLE -> Gravity.CENTER_VERTICAL
        MarkdownParser.TableVerticalAlignment.BOTTOM -> Gravity.BOTTOM
    }
}
