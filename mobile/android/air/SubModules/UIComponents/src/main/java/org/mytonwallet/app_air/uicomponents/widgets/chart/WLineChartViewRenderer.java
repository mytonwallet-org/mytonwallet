package org.mytonwallet.app_air.uicomponents.widgets.chart;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.drawable.Drawable;

import com.github.mikephil.charting.animation.ChartAnimator;
import com.github.mikephil.charting.charts.LineChart;
import com.github.mikephil.charting.data.Entry;
import com.github.mikephil.charting.highlight.Highlight;
import com.github.mikephil.charting.interfaces.datasets.ILineDataSet;
import com.github.mikephil.charting.renderer.LineChartRenderer;
import com.github.mikephil.charting.utils.Transformer;
import com.github.mikephil.charting.utils.ViewPortHandler;

public class WLineChartViewRenderer extends LineChartRenderer {
    public int grayColor = Color.GRAY;
    protected Path cubicPathRight = new Path();
    LineChart lineChart;

    public WLineChartViewRenderer(LineChart lineChart,
                                  ChartAnimator animator,
                                  ViewPortHandler viewPortHandler) {
        super(lineChart, animator, viewPortHandler);
        this.lineChart = lineChart;
    }

    @Override
    protected void drawCubicBezier(ILineDataSet dataSet) {
        Highlight[] highlights = lineChart.getHighlighted();
        boolean isHighlighted = highlights != null && highlights.length > 0;
        float highlightedX = -1;
        if (isHighlighted) {
            highlightedX = highlights[0].getX();
        }

        float phaseY = mAnimator.getPhaseY();

        Transformer trans = mChart.getTransformer(dataSet.getAxisDependency());

        mXBounds.set(mChart, dataSet);

        float intensity = dataSet.getCubicIntensity();

        cubicPath.reset();
        cubicPathRight.reset();

        if (mXBounds.range >= 1) {

            float prevDx = 0f;
            float prevDy = 0f;
            float curDx = 0f;
            float curDy = 0f;

            // Take an extra point from the left, and an extra from the right.
            // That's because we need 4 points for a cubic bezier (cubic=4), otherwise we get lines moving and doing weird stuff on the edges of the chart.
            // So in the starting `prev` and `cur`, go -2, -1
            // And in the `lastIndex`, add +1

            final int firstIndex = mXBounds.min + 1;
            final int lastIndex = mXBounds.min + mXBounds.range;

            Entry prevPrev;
            Entry prev = dataSet.getEntryForIndex(Math.max(firstIndex - 2, 0));
            Entry cur = dataSet.getEntryForIndex(Math.max(firstIndex - 1, 0));
            Entry next = cur;
            int nextIndex = -1;

            if (cur == null) return;

            Path currentPath = cubicPath;
            // let the spline start
            currentPath.moveTo(cur.getX(), cur.getY() * phaseY);

            for (int j = mXBounds.min + 1; j <= lastIndex; j++) {
                if (cur.getX() == highlightedX &&
                    currentPath != cubicPathRight) {
                    currentPath = cubicPathRight;
                    currentPath.moveTo(cur.getX(), cur.getY() * phaseY);
                }

                prevPrev = prev;
                prev = cur;
                cur = nextIndex == j ? next : dataSet.getEntryForIndex(j);

                nextIndex = j + 1 < dataSet.getEntryCount() ? j + 1 : j;
                next = dataSet.getEntryForIndex(nextIndex);

                prevDx = (cur.getX() - prevPrev.getX()) * intensity;
                prevDy = (cur.getY() - prevPrev.getY()) * intensity;
                curDx = (next.getX() - prev.getX()) * intensity;
                curDy = (next.getY() - prev.getY()) * intensity;

                currentPath.cubicTo(prev.getX() + prevDx, (prev.getY() + prevDy) * phaseY,
                    cur.getX() - curDx,
                    (cur.getY() - curDy) * phaseY, cur.getX(), cur.getY() * phaseY);
            }
        }

        // if filled is enabled, close the path
        if (dataSet.isDrawFilledEnabled()) {

            cubicFillPath.reset();
            cubicFillPath.addPath(cubicPath);
            drawCubicFill(mBitmapCanvas, dataSet, cubicFillPath, trans, mXBounds);
        }

        mRenderPaint.setColor(dataSet.getColor());

        mRenderPaint.setStyle(Paint.Style.STROKE);

        trans.pathValueToPixel(cubicPath);

        mBitmapCanvas.drawPath(cubicPath, mRenderPaint);

        if (highlightedX >= 0) {
            int originalColor = mRenderPaint.getColor();
            int lineColor = dataSet.getColor();
            int translucentColor = Color.argb(64, Color.red(lineColor), Color.green(lineColor), Color.blue(lineColor));
            mRenderPaint.setColor(translucentColor);
            trans.pathValueToPixel(cubicPathRight);
            mBitmapCanvas.drawPath(cubicPathRight, mRenderPaint);
            mRenderPaint.setColor(originalColor);
        }

        mRenderPaint.setPathEffect(null);
    }

    @Override
    protected void drawCubicFill(Canvas c, ILineDataSet dataSet, Path spline, Transformer trans, XBounds bounds) {
        Highlight[] highlights = lineChart.getHighlighted();
        boolean isHighlighted = highlights != null && highlights.length > 0;
        float highlightedX = -1;
        if (isHighlighted) {
            highlightedX = highlights[0].getX();
        }

        float fillMin = dataSet.getFillFormatter()
            .getFillLinePosition(dataSet, mChart);

        spline.lineTo(highlightedX > -1 ? highlightedX : dataSet.getEntryForIndex(bounds.min + bounds.range).getX(), fillMin);
        spline.lineTo(dataSet.getEntryForIndex(bounds.min).getX(), fillMin);
        spline.close();

        trans.pathValueToPixel(spline);

        final Drawable drawable = dataSet.getFillDrawable();
        if (drawable != null) {

            drawFilledPath(c, spline, drawable);
        } else {

            drawFilledPath(c, spline, dataSet.getFillColor(), dataSet.getFillAlpha());
        }
    }

}
