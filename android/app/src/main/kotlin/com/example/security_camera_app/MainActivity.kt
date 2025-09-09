package com.example.security_camera_app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    
    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            super.onCreate(savedInstanceState)
        } catch (e: Exception) {
            // Log do erro e tentar recuperação
            android.util.Log.e("MainActivity", "Erro durante onCreate: ${e.message}", e)
            // Tentar inicialização básica
            try {
                super.onCreate(savedInstanceState)
            } catch (e2: Exception) {
                android.util.Log.e("MainActivity", "Falha na recuperação: ${e2.message}", e2)
                finish()
            }
        }
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        try {
            super.configureFlutterEngine(flutterEngine)
            
            // Configurar canais de método com tratamento de erro
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "security_camera_app/native")
                .setMethodCallHandler { call, result ->
                    try {
                        when (call.method) {
                            "getPlatformVersion" -> {
                                result.success("Android ${android.os.Build.VERSION.RELEASE}")
                            }
                            else -> {
                                result.notImplemented()
                            }
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "Erro no MethodChannel: ${e.message}", e)
                        result.error("NATIVE_ERROR", e.message, null)
                    }
                }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Erro ao configurar FlutterEngine: ${e.message}", e)
        }
    }
    
    override fun onDestroy() {
        try {
            super.onDestroy()
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Erro durante onDestroy: ${e.message}", e)
        }
    }
}
