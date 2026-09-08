package com.klipsy.app;

/* ============================================================================
   KLİPSY — YANIT ALICI
   ============================================================================
   Kullanıcı bildirimin içine yazıp gönderdiğinde burası çalışır.
   Mesajı doğrudan sunucuya iletir; uygulamanın açılmasına gerek yoktur.

   OTURUM BİLGİSİ
     Sunucuya yazabilmek için kullanıcının oturum anahtarı gerekiyor.
     Uygulama tarafı bunu cihaz belleğine yazıyor (klipsy_oturum),
     burası oradan okuyor.

   Dosya: android/app/src/main/java/com/klipsy/app/KlipsyYanitAlici.java
   ============================================================================ */

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;

import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.app.Person;
import androidx.core.app.RemoteInput;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;

public class KlipsyYanitAlici extends BroadcastReceiver {

    private static final int RENK = 0xFFFF3B6B;

    /* Son hatanın sebebi — bildirimde gösterilir.
       "Gönderilemedi" tek başına yetersizdi; nerede takıldığı
       anlaşılmıyordu. */
    private String sonHata = "";

    @Override
    public void onReceive(final Context baglam, Intent niyet) {

        /* SESSİZE AL — yanıt değil, ayrı bir eylem. */
        if (KlipsyMesajServisi.EYLEM_SESSIZ.equals(niyet.getAction())) {
            sessizeAl(baglam, niyet);
            return;
        }

        Bundle girdi = RemoteInput.getResultsFromIntent(niyet);
        if (girdi == null) return;

        CharSequence ham = girdi.getCharSequence(KlipsyMesajServisi.YANIT_ANAHTARI);
        if (ham == null) return;

        final String metin = ham.toString().trim();
        if (metin.isEmpty()) return;

        final String kullanici = niyet.getStringExtra(KlipsyMesajServisi.EK_KISI);
        final String hedefId   = niyet.getStringExtra(KlipsyMesajServisi.EK_HEDEF_ID);
        final int bildirimId   = niyet.getIntExtra(KlipsyMesajServisi.EK_BILDIRIM, 0);

        /* Kullanıcıya hemen geri bildirim. */
        gonderiliyorGoster(baglam, bildirimId, metin);
        izBirak(baglam, "yanıt denendi: " + metin.substring(0, Math.min(20, metin.length())));

        /* goAsync() ŞART.
           Alıcının ömrü kısa; normal bir iş parçacığı başlatınca sistem
           işlem bitmeden alıcıyı kapatabiliyor ve yanıt kayboluyordu.
           goAsync ile işlem bitene kadar canlı kalır. */
        final PendingResult bekleyen = goAsync();

        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    boolean basarili = mesajGonder(baglam, hedefId, kullanici, metin);

                    if (basarili) {
                        izBirak(baglam, "yanıt GÖNDERİLDİ");

                        /* Yanıt verildi: bildirimdeki sohbet geçmişi temizlenir,
                           bir sonraki mesaj temiz başlasın. */
                        try {
                            String konusma = niyet.getStringExtra(KlipsyMesajServisi.EK_KONUSMA);
                            String anahtar = "klipsy_conv_" +
                                    ((konusma == null || konusma.isEmpty())
                                        ? (kullanici == null ? "genel" : kullanici)
                                        : konusma);
                            baglam.getSharedPreferences("KlipsySohbetGecmisi", Context.MODE_PRIVATE)
                                  .edit().remove(anahtar).apply();
                        } catch (Throwable t) { }

                        NotificationManagerCompat.from(baglam).cancel(bildirimId);
                    } else {
                        izBirak(baglam, "yanıt başarısız: " + sonHata);
                        basarisizGoster(baglam, bildirimId, metin, sonHata);
                    }
                } catch (Throwable t) {
                    String h = t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage());
                    izBirak(baglam, "yanıt başarısız: " + h);
                    basarisizGoster(baglam, bildirimId, metin, h);
                } finally {
                    bekleyen.finish();
                }
            }
        }).start();
    }

    /* ═══ SESSİZE AL ═══
       Sohbeti susturur ve bildirimi kapatır. Uygulamayı açmaya
       gerek kalmıyor. Mesajlaşmadaki özelliğin aynısı — aynı
       tabloyu kullanıyor. */
    private void sessizeAl(final Context baglam, Intent niyet) {
        final String konusma = niyet.getStringExtra(KlipsyMesajServisi.EK_KONUSMA);
        final String kullanici = niyet.getStringExtra(KlipsyMesajServisi.EK_KISI);
        final int bildirimId = niyet.getIntExtra(KlipsyMesajServisi.EK_BILDIRIM, 0);

        /* Bildirimi hemen kapat — kullanıcı beklemesin. */
        try { NotificationManagerCompat.from(baglam).cancel(bildirimId); }
        catch (Throwable t) { }

        izBirak(baglam, "sessize alınıyor: " + kullanici);

        final PendingResult bekleyen = goAsync();
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    if (konusma == null || konusma.isEmpty()) {
                        izBirak(baglam, "sessize alma: konuşma kimliği yok");
                        return;
                    }

                    SharedPreferences ayar =
                            baglam.getSharedPreferences("CapacitorStorage", Context.MODE_PRIVATE);
                    String adres   = ayarOku(ayar, "klipsy_sb_url");
                    String anahtar = ayarOku(ayar, "klipsy_sb_key");
                    String oturum  = ayarOku(ayar, "klipsy_oturum");
                    String tazeleme = ayarOku(ayar, "klipsy_tazeleme");

                    if (adres == null || anahtar == null || oturum == null) {
                        izBirak(baglam, "sessize alma: oturum yok");
                        return;
                    }

                    boolean tamam = sessizYaz(baglam, adres, anahtar, oturum, konusma);

                    /* Oturum süresi dolmuşsa tazeleyip bir kez daha dene. */
                    if (!tamam && tazeleme != null) {
                        String yeni = oturumTazele(baglam, adres, anahtar, tazeleme);
                        if (yeni != null) {
                            tamam = sessizYaz(baglam, adres, anahtar, yeni, konusma);
                        }
                    }

                    izBirak(baglam, tamam ? "SESSİZE ALINDI" : "sessize alma başarısız");

                    /* Sohbet geçmişi de temizlenir. */
                    if (tamam) {
                        try {
                            baglam.getSharedPreferences("KlipsySohbetGecmisi", Context.MODE_PRIVATE)
                                  .edit().remove("klipsy_conv_" + konusma).apply();
                        } catch (Throwable t) { }
                    }
                } catch (Throwable t) {
                    izBirak(baglam, "sessize alma hatası: " + t.getClass().getSimpleName());
                } finally {
                    bekleyen.finish();
                }
            }
        }).start();
    }

    /* Sessize alma kaydını sunucuya yazar. */
    private boolean sessizYaz(Context baglam, String adres, String anahtar,
                              String oturum, String konusma) {
        HttpURLConnection b = null;
        try {
            JSONObject govde = new JSONObject();
            govde.put("conv", konusma);

            URL url = new URL(adres + "/rest/v1/rpc/mute_conversation");
            b = (HttpURLConnection) url.openConnection();
            b.setRequestMethod("POST");
            b.setConnectTimeout(8000);
            b.setReadTimeout(8000);
            b.setDoOutput(true);
            b.setRequestProperty("Content-Type", "application/json");
            b.setRequestProperty("apikey", anahtar);
            b.setRequestProperty("Authorization", "Bearer " + oturum);

            OutputStream cikis = b.getOutputStream();
            cikis.write(govde.toString().getBytes("UTF-8"));
            cikis.close();

            int kod = b.getResponseCode();
            return kod >= 200 && kod < 300;
        } catch (Exception e) {
            return false;
        } finally {
            if (b != null) b.disconnect();
        }
    }

    /* Son olayı cihaz belleğine yazar; uygulama tanılama raporunda gösterir. */
    private void izBirak(Context baglam, String metin) {
        try {
            SharedPreferences ayar =
                    baglam.getSharedPreferences("KlipsyServisIz", Context.MODE_PRIVATE);
            String zaman = new java.text.SimpleDateFormat("HH:mm:ss",
                    java.util.Locale.getDefault()).format(new java.util.Date());
            String eski = ayar.getString("iz", "");
            String yeni = zaman + " " + metin + (eski.isEmpty() ? "" : ("\n" + eski));
            if (yeni.length() > 600) yeni = yeni.substring(0, 600);
            ayar.edit().putString("iz", yeni).apply();
        } catch (Throwable ignored) { }
    }

    /* ── Sunucuya gönder ── */
    private boolean mesajGonder(Context baglam, String hedefIdGelen,
                                String kullanici, String metin) {

        SharedPreferences ayar =
                baglam.getSharedPreferences("CapacitorStorage", Context.MODE_PRIVATE);

        String adres    = ayarOku(ayar, "klipsy_sb_url");
        String anahtar  = ayarOku(ayar, "klipsy_sb_key");
        String oturum   = ayarOku(ayar, "klipsy_oturum");
        String tazeleme = ayarOku(ayar, "klipsy_tazeleme");

        if (adres == null)   { sonHata = "adres yok"; return false; }
        if (anahtar == null) { sonHata = "anahtar yok"; return false; }
        if (oturum == null)  { sonHata = "oturum yok — uygulamayı açıp bekle"; return false; }

        HttpURLConnection baglanti = null;
        try {
            /* Hedef kimliği bildirimle birlikte geliyorsa doğrudan
               kullanılır — fazladan sorgu yapılmaz. Gelmiyorsa (eski
               bildirimler) kullanıcı adından çözülür. */
            String hedefId = (hedefIdGelen != null && !hedefIdGelen.isEmpty())
                    ? hedefIdGelen
                    : kullaniciKimligi(adres, anahtar, oturum, kullanici);

            if (hedefId == null || hedefId.isEmpty()) {
                sonHata = "hedef bulunamadı: " + kullanici;
                return false;
            }

            JSONObject govde = new JSONObject();
            govde.put("to_user", hedefId);
            govde.put("msg_kind", "text");
            govde.put("msg_body", metin);

            URL url = new URL(adres + "/rest/v1/rpc/send_message");
            baglanti = (HttpURLConnection) url.openConnection();
            baglanti.setRequestMethod("POST");
            baglanti.setConnectTimeout(8000);
            baglanti.setReadTimeout(8000);
            baglanti.setDoOutput(true);
            baglanti.setRequestProperty("Content-Type", "application/json");
            baglanti.setRequestProperty("apikey", anahtar);
            baglanti.setRequestProperty("Authorization", "Bearer " + oturum);

            OutputStream cikis = baglanti.getOutputStream();
            cikis.write(govde.toString().getBytes("UTF-8"));
            cikis.close();

            int kod = baglanti.getResponseCode();
            if (kod >= 200 && kod < 300) return true;

            /* OTURUM SÜRESİ DOLMUŞ (401)
               Anahtarlar yaklaşık bir saatte geçersizleşiyor. Kullanıcı
               bildirime saatler sonra yanıt verdiğinde "JWT expired"
               hatası alınıyordu. Tazeleme anahtarıyla yeni bir oturum
               alınır ve gönderim BİR KEZ tekrarlanır. */
            if (kod == 401 && tazeleme != null && !yenidenDenendi) {
                String yeniOturum = oturumTazele(baglam, adres, anahtar, tazeleme);
                if (yeniOturum != null) {
                    yenidenDenendi = true;
                    baglanti.disconnect();
                    return mesajGonder(baglam, hedefIdGelen, kullanici, metin);
                }
            }

            // sunucunun döndürdüğü hata metnini oku
            String detay = "";
            try {
                java.io.InputStream hataAkisi = baglanti.getErrorStream();
                if (hataAkisi != null) {
                    BufferedReader r = new BufferedReader(new InputStreamReader(hataAkisi, "UTF-8"));
                    StringBuilder sb2 = new StringBuilder();
                    String sat;
                    while ((sat = r.readLine()) != null) sb2.append(sat);
                    r.close();
                    detay = sb2.toString();
                    if (detay.length() > 90) detay = detay.substring(0, 90);
                }
            } catch (Exception ignored) { }

            sonHata = "sunucu " + kod + (detay.isEmpty() ? "" : (": " + detay));
            return false;
        } catch (Exception e) {
            sonHata = e.getClass().getSimpleName() + ": " +
                      (e.getMessage() == null ? "" : e.getMessage());
            if (sonHata.length() > 110) sonHata = sonHata.substring(0, 110);
            return false;
        } finally {
            if (baglanti != null) baglanti.disconnect();
        }
    }

    /* Sonsuz döngüyü önlemek için: tazeleme yalnızca bir kez denenir. */
    private boolean yenidenDenendi = false;

    /* OTURUM TAZELEME
       Tazeleme anahtarıyla yeni bir erişim anahtarı alır ve cihaz
       belleğine yazar. Böylece sonraki yanıtlar da çalışır. */
    private String oturumTazele(Context baglam, String adres,
                                String anahtar, String tazeleme) {
        HttpURLConnection b = null;
        try {
            URL url = new URL(adres + "/auth/v1/token?grant_type=refresh_token");
            b = (HttpURLConnection) url.openConnection();
            b.setRequestMethod("POST");
            b.setConnectTimeout(8000);
            b.setReadTimeout(8000);
            b.setDoOutput(true);
            b.setRequestProperty("Content-Type", "application/json");
            b.setRequestProperty("apikey", anahtar);

            JSONObject govde = new JSONObject();
            govde.put("refresh_token", tazeleme);

            OutputStream cikis = b.getOutputStream();
            cikis.write(govde.toString().getBytes("UTF-8"));
            cikis.close();

            if (b.getResponseCode() < 200 || b.getResponseCode() >= 300) return null;

            BufferedReader r = new BufferedReader(
                    new InputStreamReader(b.getInputStream(), "UTF-8"));
            StringBuilder sb = new StringBuilder();
            String satir;
            while ((satir = r.readLine()) != null) sb.append(satir);
            r.close();

            JSONObject cevap = new JSONObject(sb.toString());
            String yeni = cevap.optString("access_token", null);
            String yeniTazeleme = cevap.optString("refresh_token", null);
            if (yeni == null || yeni.isEmpty()) return null;

            // yeni anahtarları sakla
            SharedPreferences ayar =
                    baglam.getSharedPreferences("CapacitorStorage", Context.MODE_PRIVATE);
            SharedPreferences.Editor d = ayar.edit();
            d.putString("klipsy_oturum", yeni);
            if (yeniTazeleme != null && !yeniTazeleme.isEmpty()) {
                d.putString("klipsy_tazeleme", yeniTazeleme);
            }
            d.apply();

            izBirak(baglam, "oturum tazelendi");
            return yeni;
        } catch (Exception e) {
            return null;
        } finally {
            if (b != null) b.disconnect();
        }
    }

    /* AYAR OKUMA
       Capacitor'ın tercih eklentisi, sürümüne göre anahtarları düz adla
       ya da "_cap_" ön ekiyle saklıyor. Düz adla aranınca bulunamıyor ve
       "adres yok" hatası çıkıyordu. Her iki biçim de denenir. */
    private String ayarOku(SharedPreferences ayar, String anahtar) {
        String v = ayar.getString(anahtar, null);
        if (v != null) return v;

        v = ayar.getString("_cap_" + anahtar, null);
        if (v != null) return temizle(v);

        return null;
    }

    /* Bazı sürümler değeri tırnak içinde saklıyor. */
    private String temizle(String v) {
        if (v == null) return null;
        String t = v.trim();
        if (t.length() >= 2 && t.startsWith("\"") && t.endsWith("\"")) {
            return t.substring(1, t.length() - 1);
        }
        return t;
    }

    /* Kullanıcı adından kimlik çöz. */
    private String kullaniciKimligi(String adres, String anahtar,
                                    String oturum, String kullanici) {
        HttpURLConnection baglanti = null;
        try {
            String ad = URLEncoder.encode(kullanici, "UTF-8");
            URL url = new URL(adres + "/rest/v1/profiles?select=id&username=eq." + ad + "&limit=1");

            baglanti = (HttpURLConnection) url.openConnection();
            baglanti.setRequestMethod("GET");
            baglanti.setConnectTimeout(8000);
            baglanti.setReadTimeout(8000);
            baglanti.setRequestProperty("apikey", anahtar);
            baglanti.setRequestProperty("Authorization", "Bearer " + oturum);

            BufferedReader okuyucu = new BufferedReader(
                    new InputStreamReader(baglanti.getInputStream(), "UTF-8"));
            StringBuilder sb = new StringBuilder();
            String satir;
            while ((satir = okuyucu.readLine()) != null) sb.append(satir);
            okuyucu.close();

            JSONArray dizi = new JSONArray(sb.toString());
            if (dizi.length() == 0) return null;
            return dizi.getJSONObject(0).getString("id");
        } catch (Exception e) {
            return null;
        } finally {
            if (baglanti != null) baglanti.disconnect();
        }
    }

    /* ── Geri bildirim ── */
    private void gonderiliyorGoster(Context baglam, int bildirimId, String metin) {
        NotificationCompat.MessagingStyle stil =
                new NotificationCompat.MessagingStyle(new Person.Builder().setName("Sen").build())
                        .addMessage(metin, System.currentTimeMillis(), (Person) null);

        NotificationCompat.Builder yapici =
                new NotificationCompat.Builder(baglam, KlipsyMesajServisi.KANAL_MESAJ)
                        .setSmallIcon(android.R.drawable.ic_dialog_email)
                        .setColor(RENK)
                        .setStyle(stil)
                        .setOnlyAlertOnce(true);

        try {
            NotificationManagerCompat.from(baglam).notify(bildirimId, yapici.build());
        } catch (SecurityException e) {
            // izin yok
        }
    }

    private void basarisizGoster(Context baglam, int bildirimId,
                                 String metin, String sebep) {
        String aciklama = (sebep == null || sebep.isEmpty()) ? metin : sebep;

        NotificationCompat.Builder yapici =
                new NotificationCompat.Builder(baglam, KlipsyMesajServisi.KANAL_MESAJ)
                        .setSmallIcon(android.R.drawable.stat_notify_error)
                        .setColor(RENK)
                        .setContentTitle("Mesaj gönderilemedi")
                        .setContentText(aciklama)
                        .setStyle(new NotificationCompat.BigTextStyle()
                                .bigText("Yazdığın: " + metin + "\n\nSebep: " + aciklama))
                        .setAutoCancel(true);

        try {
            NotificationManagerCompat.from(baglam).notify(bildirimId, yapici.build());
        } catch (SecurityException e) {
            // izin yok
        }
    }
}
