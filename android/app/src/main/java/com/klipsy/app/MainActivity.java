package com.klipsy.app;

import android.content.Intent;
import android.os.Bundle;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.os.Build;
import android.graphics.Color;
import android.view.Window;

import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;

import com.getcapacitor.BridgeActivity;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginHandle;

import ee.forgr.capacitor.social.login.GoogleProvider;
import ee.forgr.capacitor.social.login.SocialLoginPlugin;
import ee.forgr.capacitor.social.login.ModifiedMainActivityForSocialLoginPlugin;

public class MainActivity extends BridgeActivity
        implements ModifiedMainActivityForSocialLoginPlugin {

    @Override
    public void onStart() {
        super.onStart();
        try {
            getBridge().getWebView().setWebChromeClient(new android.webkit.WebChromeClient() {
                @Override
                public void onPermissionRequest(final android.webkit.PermissionRequest request) {
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            request.grant(request.getResources());
                        }
                    });
                }
            });
        } catch (Exception e) {
            android.util.Log.w("Klipsy", "kamera izin koprusu kurulamadi: " + e);
        }
    }


    {
        registerPlugin(KlipsyIzEklentisi.class);
    }

    @Override
    public void onCreate(Bundle savedInstanceState) {
        // Manifest'te Activity'ye splash teması (Theme.SplashScreen) atanmış
        // ve hiç değiştirilmiyordu — bu yüzden AppTheme.NoActionBar içindeki
        // windowOptOutEdgeToEdgeEnforcement / statusBarColor / windowLightStatusBar
        // hiçbir zaman devreye girmiyordu ve Android 15 uygulamayı sürekli
        // zorunlu edge-to-edge modda tutuyordu (kameradan bağımsız, kalıcı olarak).
        setTheme(R.style.AppTheme_NoActionBar);
        super.onCreate(savedInstanceState);
        hideSystemBars();
        // Pencere/cubuk rengi BURADAN ayarlanmaz.
        // targetSdk 35+ icin setStatusBarColor/setNavigationBarColor no-op.
        // Renk: CSS #sysBarBg + SafeArea eklentisi.
    }

    @Override
    public void onResume() {
        super.onResume();
        if (getBridge() != null && getBridge().getWebView() != null) {
            getBridge().getWebView().getSettings().setTextZoom(100);
            getBridge().getWebView().getSettings().setSupportZoom(false);
        }
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);

        if (requestCode >= GoogleProvider.REQUEST_AUTHORIZE_GOOGLE_MIN
                && requestCode < GoogleProvider.REQUEST_AUTHORIZE_GOOGLE_MAX) {

            PluginHandle handle = getBridge().getPlugin("SocialLogin");
            if (handle == null) return;

            Plugin plugin = handle.getInstance();
            if (!(plugin instanceof SocialLoginPlugin)) return;

            ((SocialLoginPlugin) plugin).handleGoogleLoginIntent(requestCode, data);
        }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) hideSystemBars();
    }

    private void hideSystemBars() {
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        WindowInsetsControllerCompat c =
                WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
        if (c != null) {
            c.hide(WindowInsetsCompat.Type.navigationBars());
            c.setSystemBarsBehavior(
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
        }
    }

    @Override
    public void IHaveModifiedTheMainActivityForTheUseWithSocialLoginPlugin() {}
}
