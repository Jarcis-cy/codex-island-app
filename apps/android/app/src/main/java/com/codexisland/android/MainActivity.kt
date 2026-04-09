package com.codexisland.android

import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val textView = TextView(this).apply {
            text = getString(R.string.bootstrap_message)
            setPadding(48, 96, 48, 48)
        }

        setContentView(textView)
    }
}
