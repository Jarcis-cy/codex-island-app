package com.codexisland.android

import android.widget.TextView
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class MainActivityTest {
    @Test
    fun showsBootstrapWorkspaceTitle() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val title = activity.findViewById<TextView>(R.id.shellHeaderTitle)

        assertEquals(
            activity.getString(R.string.shell_header_title),
            title.text.toString()
        )
    }
}
