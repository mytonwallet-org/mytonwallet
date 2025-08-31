package org.mytonwallet.app_air.uicomponents.helpers;

import android.graphics.Rect;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

public class SpacesItemDecoration extends RecyclerView.ItemDecoration {

    private final int spaceX;
    private final int spaceY;

    public SpacesItemDecoration(int spaceX,
                                int spaceY) {
        this.spaceX = spaceX;
        this.spaceY = spaceY;
    }

    @Override
    public void getItemOffsets(@NonNull Rect outRect, @NonNull View view, @NonNull RecyclerView parent, @NonNull RecyclerView.State state) {
        outRect.left = spaceX / 2;
        outRect.right = spaceX / 2;
        outRect.top = spaceY / 2;
        outRect.bottom = spaceY / 2;
    }
}
