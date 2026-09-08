package com.klipsy.app;

/* ============================================================================
   KLİPSY — SERVİS İZİ OKUYUCU
   ============================================================================
   Bildirim servisi ve yanıt alıcısı, yerel kodda çalışıyor. Oradaki
   kayıtları uygulamadan göremiyoruz; sorunun nerede olduğunu anlamak
   bu yüzden çok zorlaştı.

   Bu eklenti, servislerin bıraktığı izleri uygulamaya taşır.
   Ayarlar'daki tanılama raporunda görünür.

   Dosya: android/app/src/main/java/com/klipsy/app/KlipsyIzEklentisi.java
   Kayıt: MainActivity içinde registerPlugin(KlipsyIzEklentisi.class)
   ============================================================================ */

import android.content.Context;
import android.content.SharedPreferences;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "KlipsyIz")
public class KlipsyIzEklentisi extends Plugin {

    /* Bir sohbetin bildirimini kapatır.
       Belge: kullanıcı mesajı okuduğunda bildirim iptal edilmeli.
       Uygulama sohbeti açınca burası çağrılır. */
    @PluginMethod
    public void sohbetBildiriminiKapat(PluginCall cagri) {
        try {
            String konusma = cagri.getString("conv", "");
            String kullanici = cagri.getString("who", "");

            String temel = (konusma != null && !konusma.trim().isEmpty())
                    ? konusma
                    : ((kullanici == null || kullanici.isEmpty()) ? "genel" : kullanici);
            String anahtar = "klipsy_conv_" + temel;

            /* Bildirim kimliği konuşma kimliğinin sayısal karşılığı. */
            int bildirimId = (konusma == null || konusma.isEmpty())
                    ? temel.hashCode() : konusma.hashCode();

            androidx.core.app.NotificationManagerCompat
                    .from(getContext()).cancel(bildirimId);

            /* Sohbet geçmişi de temizlenir: bir sonraki bildirim
               okunmuş mesajları tekrar göstermesin. */
            getContext().getSharedPreferences("KlipsySohbetGecmisi", Context.MODE_PRIVATE)
                        .edit().remove(anahtar).apply();

            cagri.resolve();
        } catch (Throwable t) {
            cagri.resolve();
        }
    }

    /* Servislerin bıraktığı izleri döndürür. */
    @PluginMethod
    public void izleriOku(PluginCall cagri) {
        SharedPreferences ayar = getContext()
                .getSharedPreferences("KlipsyServisIz", Context.MODE_PRIVATE);

        JSObject sonuc = new JSObject();
        sonuc.put("iz", ayar.getString("iz", ""));
        cagri.resolve(sonuc);
    }

    /* İzleri temizler. */
    @PluginMethod
    public void izleriTemizle(PluginCall cagri) {
        getContext().getSharedPreferences("KlipsyServisIz", Context.MODE_PRIVATE)
                .edit().remove("iz").apply();
        cagri.resolve();
    }

    /* Oturum bilgisinin yerel tarafta GERÇEKTEN görünüp görünmediğini
       söyler. "adres yok" hatasının sebebini burada görebiliriz. */
    @PluginMethod
    public void ayarDurumu(PluginCall cagri) {
        SharedPreferences ayar = getContext()
                .getSharedPreferences("CapacitorStorage", Context.MODE_PRIVATE);

        JSObject sonuc = new JSObject();
        sonuc.put("url_duz",    ayar.contains("klipsy_sb_url"));
        sonuc.put("url_onekli", ayar.contains("_cap_klipsy_sb_url"));
        sonuc.put("oturum_duz",    ayar.contains("klipsy_oturum"));
        sonuc.put("oturum_onekli", ayar.contains("_cap_klipsy_oturum"));

        /* Dosyada hangi anahtarlar var — ilk 12 tanesi. */
        StringBuilder liste = new StringBuilder();
        int i = 0;
        for (String k : ayar.getAll().keySet()) {
            if (i++ >= 12) break;
            liste.append(k).append("\n");
        }
        sonuc.put("anahtarlar", liste.toString());

        cagri.resolve(sonuc);
    }
}
