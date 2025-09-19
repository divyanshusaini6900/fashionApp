package com.ratnawnai.RatNawnAI

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var batteryOptimizationManager: BatteryOptimizationManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Configure battery optimization manager
        batteryOptimizationManager = BatteryOptimizationManager(this)
        batteryOptimizationManager.configureChannel(flutterEngine)
    }
}