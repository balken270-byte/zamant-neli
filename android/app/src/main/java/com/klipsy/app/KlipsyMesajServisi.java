package com.klipsy.app;

/* ============================================================================
   KLİPSY — BİLDİRİM SERVİSİ
   ============================================================================
   NE YAPAR
     Mesaj bildirimine "Yanıtla" düğmesi ekler. Kullanıcı uygulamayı hiç
     açmadan bildirimin içinden yazıp gönderebilir (WhatsApp'taki gibi).
     Diğer bildirimleri (beğeni, yorum, takip) de görselleriyle gösterir.

   NEDEN YEREL KOD
     Android'in doğrudan yanıt özelliği yalnızca yerel bildirim kurulumunda
     çalışıyor; tarayıcı katmanından yapılamıyor.

   NEDEN JAVA
     Proje Java tabanlı. Kotlin eklemek, Capacitor eklentilerinin kendi
     Kotlin sürümüyle çakışıyor ve derlemeyi bozuyor.

   NASIL ÇALIŞIR
     1. Sunucu mesaj bildirimini SADECE VERİ olarak gönderir.
        (Hazır bildirim gönderilirse Android kendi gösterir ve bu servis
         hiç çağrılmaz.)
     2. Bu servis bildirimi kendisi kurar, yanıt alanını ekler.
     3. Kullanıcı yazıp gönderince KlipsyYanitAlici devreye girer.

   Dosya: android/app/src/main/java/com/klipsy/app/KlipsyMesajServisi.java
   ============================================================================ */

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.BitmapFactory;
import android.os.Build;

import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.app.Person;
import androidx.core.app.RemoteInput;
import androidx.core.content.pm.ShortcutInfoCompat;
import androidx.core.content.pm.ShortcutManagerCompat;
import androidx.core.content.LocusIdCompat;
import androidx.core.graphics.drawable.IconCompat;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import java.io.InputStream;
import java.net.URL;
import java.net.URLConnection;
import java.util.Map;

public class KlipsyMesajServisi extends FirebaseMessagingService {

    /* KANAL SÜRÜMÜ v2 — KRİTİK
       Android'de bir kanalın önem seviyesi, oluşturulduktan sonra kodla
       yükseltilemiyor. Eski "klipsy_mesaj" kanalı düşük seviyede
       kaldığı için bildirim sesi çıkıyor ama kart görünmüyordu.
       Yeni kimlikle kanal sıfırdan, yüksek seviyede kuruluyor. */
    public static final String KANAL_MESAJ    = "klipsy_mesaj_v2";
    private static final String KANAL_MESAJ_ESKI = "klipsy_mesaj";
    public static final String KANAL_GENEL    = "klipsy";
    public static final String YANIT_ANAHTARI = "klipsy_yanit_metni";
    public static final String EK_KONUSMA     = "konusma_id";
    public static final String EK_KISI        = "kisi_adi";
    public static final String EK_HEDEF_ID    = "hedef_kullanici_id";
    public static final String EYLEM_SESSIZ    = "com.klipsy.app.SESSIZE_AL";
    public static final String EK_BILDIRIM    = "bildirim_id";

    private static final int RENK = 0xFFFF3B6B;

    /* YIĞINLAMA
       Aynı gruptaki bildirimler tek kartta toplanır. Android bunun için
       her bildirime bir grup adı, ayrıca gruba bir "özet" bildirimi
       ister. Özet kapalı görünümü, tek tek bildirimler ise açılınca
       görünen satırları oluşturur. */
    public static final String GRUP_ETKILESIM = "klipsy_etkilesim";
    private static final int OZET_ID = 999000;

    /* Açılınca görünecek satırlar burada birikir. */
    private static final java.util.LinkedList<String> yiginSatirlari =
            new java.util.LinkedList<>();

    @Override
    public void onCreate() {
        super.onCreate();
        kanallariKur();
    }

    @Override
    public void onMessageReceived(RemoteMessage mesaj) {
        super.onMessageReceived(mesaj);

        Map<String, String> veri = mesaj.getData();

        /* YEDEK: Bazı durumlarda veri boş gelip bilgi "notification"
           bölümünde olabiliyor. O zaman bildirim boş görünüyordu.
           İkisini de kontrol ediyoruz. */
        RemoteMessage.Notification n = mesaj.getNotification();
        if (n != null) {
            java.util.HashMap<String, String> birlesik = new java.util.HashMap<>();
            if (veri != null) birlesik.putAll(veri);
            if (birlesik.get("title") == null && n.getTitle() != null)
                birlesik.put("title", n.getTitle());
            if (birlesik.get("body") == null && n.getBody() != null)
                birlesik.put("body", n.getBody());
            veri = birlesik;
        }

        String tur = deger(veri, "kind", "");

        /* İZ BIRAK — servisin çalışıp çalışmadığını uygulamadan
           görebilmek için. Yerel kodun kayıtlarını okuyamıyoruz;
           bu iz Ayarlar'daki tanılama raporunda görünür. */
        izBirak("geldi tür=" + tur + " alan=" + (veri == null ? 0 : veri.size()));

        /* Bir hata olursa bildirim HİÇ ÇIKMIYORDU — kullanıcı mesajı
           hiç göremiyordu. Artık en kötü durumda sade bir bildirim
           gösteriliyor. */
        try {
            if ("message".equals(tur)) {
                mesajBildirimi(veri);
            } else {
                genelBildirim(veri);
            }
        } catch (Throwable t) {
            basitBildirim(veri, tur);
        }
    }

    /* Son olayı cihaz belleğine yazar. Uygulama bunu okuyup
       tanılama raporunda gösterir. */
    private void izBirak(String metin) {
        try {
            android.content.SharedPreferences ayar =
                    getSharedPreferences("KlipsyServisIz", Context.MODE_PRIVATE);
            String zaman = new java.text.SimpleDateFormat("HH:mm:ss",
                    java.util.Locale.getDefault()).format(new java.util.Date());
            String eski = ayar.getString("iz", "");
            String yeni = zaman + " " + metin + (eski.isEmpty() ? "" : ("\n" + eski));
            if (yeni.length() > 600) yeni = yeni.substring(0, 600);
            ayar.edit().putString("iz", yeni).apply();
        } catch (Throwable ignored) { }
    }

    /* Süslemesiz yedek bildirim. */
    private void basitBildirim(Map<String, String> veri, String tur) {
        try {
            String baslik = deger(veri, "title", "Klipsy");
            String metin  = deger(veri, "body", "");
            int id = (baslik + metin).hashCode();

            NotificationCompat.Builder y = new NotificationCompat.Builder(
                    this, "message".equals(tur) ? KANAL_MESAJ : KANAL_GENEL)
                    .setSmallIcon(uygulamaSimgesi())
                    .setColor(RENK)
                    .setContentTitle(baslik)
                    .setContentText(metin)
                    .setContentIntent(acmaNiyeti(id, tur, deger(veri, "actor", ""),
                                                 deger(veri, "moment_id", "")))
                    .setAutoCancel(true)
                    .setPriority(NotificationCompat.PRIORITY_HIGH);
            gonder(id, y);
        } catch (Throwable ignored) { }
    }

    /* KÜÇÜK SİMGE HAKKINDA
       Android bildirimlerde küçük simgeyi ZORUNLU tutuyor; kaldırmanın
       yolu yok. Ama küçük ve tek renk çizilir, sadece rozet gibi durur.
       Asıl görsel büyük simgedir — orada kullanıcının fotoğrafı var.

       Simge sırası:
         1. ic_stat_klipsy  — bildirimler için özel çizilmiş, sade
         2. ic_notification — ikinci ad denemesi
         3. uygulama simgesi — hiçbiri yoksa

       En iyisi tek renk, sade bir çizim koymak: renkli uygulama
       simgesi bildirim çubuğunda beyaz kare olarak görünüyor. */
    private int uygulamaSimgesi() {
        int id = getResources().getIdentifier("ic_stat_klipsy", "drawable", getPackageName());
        if (id != 0) return id;
        id = getResources().getIdentifier("ic_notification", "drawable", getPackageName());
        if (id != 0) return id;
        id = getResources().getIdentifier("ic_launcher_foreground", "mipmap", getPackageName());
        if (id != 0) return id;
        return getApplicationInfo().icon;
    }

    /* ── Mesaj bildirimi: yanıt alanı ile ── */
    private void mesajBildirimi(Map<String, String> veri) {
        String gonderen = deger(veri, "title", "");
        String metin    = deger(veri, "body",  "");
        if (gonderen.trim().isEmpty()) gonderen = "Klipsy";
        if (metin.trim().isEmpty())    metin    = "Yeni mesaj";

        String konusma     = deger(veri, "conv_id", "");
        String kullanici   = deger(veri, "actor",   "");
        String hedefId     = deger(veri, "actor_id", "");
        String avatarAdres = deger(veri, "avatar",  "");

        int bildirimId = konusma.isEmpty() ? gonderen.hashCode() : konusma.hashCode();

        /* Gönderenin fotoğrafı — bildirimin ana görseli. */
        /* Belge 104 dp avatar öneriyor; yoğun ekranlarda bu yaklaşık
           320 piksel eder. Daha küçüğü bulanık görünüyor ve sistem
           bazen yerine baş harfleri koyuyor. */
        Bitmap avatar = yuvarlatilmisKare(gorselIndir(avatarAdres), 320, 70f);

        /* PROFİL FOTOĞRAFI YOKSA BAŞ HARF ÇİZİLİR.
           Önceden sistem bildirim simgesi görünüyordu; uygulamada
           baş harfli renkli avatarlar var, bildirimde de aynısı olmalı. */
        if (avatar == null) avatar = basHarfAvatari(gonderen, kullanici, 320);

        /* ── Yanıtla düğmesi ── */
        RemoteInput yanitGirdisi = new RemoteInput.Builder(YANIT_ANAHTARI)
                .setLabel("Yanıtla…").build();

        Intent yanitNiyeti = new Intent(this, KlipsyYanitAlici.class);
        yanitNiyeti.putExtra(EK_KONUSMA, konusma);
        yanitNiyeti.putExtra(EK_KISI, kullanici);
        yanitNiyeti.putExtra(EK_HEDEF_ID, hedefId);
        yanitNiyeti.putExtra(EK_BILDIRIM, bildirimId);

        int bayrakYanit = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            bayrakYanit |= PendingIntent.FLAG_MUTABLE;
        }
        PendingIntent yanitBekleyen = PendingIntent.getBroadcast(
                this, bildirimId, yanitNiyeti, bayrakYanit);

        NotificationCompat.Action yanitEylemi =
                new NotificationCompat.Action.Builder(
                        android.R.drawable.ic_menu_send, "Yanıtla", yanitBekleyen)
                        .addRemoteInput(yanitGirdisi)
                        .setAllowGeneratedReplies(true)
                        .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
                        .setShowsUserInterface(false)
                        .build();

        PendingIntent acmaBekleyen = acmaNiyeti(bildirimId + 1, "message", kullanici, "");

        /* ── SESSİZE AL düğmesi ──
           Uygulamayı açmadan o sohbeti susturmak için. Mesajlaşmada
           zaten var olan özelliğin bildirimdeki karşılığı. */
        Intent sessizNiyeti = new Intent(this, KlipsyYanitAlici.class);
        sessizNiyeti.setAction(EYLEM_SESSIZ);
        sessizNiyeti.putExtra(EK_KONUSMA, konusma);
        sessizNiyeti.putExtra(EK_KISI, kullanici);
        sessizNiyeti.putExtra(EK_BILDIRIM, bildirimId);

        int bayrakSessiz = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            bayrakSessiz |= PendingIntent.FLAG_IMMUTABLE;
        }
        PendingIntent sessizBekleyen = PendingIntent.getBroadcast(
                this, bildirimId + 2, sessizNiyeti, bayrakSessiz);

        NotificationCompat.Action sessizEylemi =
                new NotificationCompat.Action.Builder(
                        android.R.drawable.ic_lock_silent_mode,
                        "Sessize al", sessizBekleyen)
                        .setShowsUserInterface(false)
                        .build();

        /* ── SOHBET BİÇİMİ (WhatsApp görünümü) ──
           Bir kez kısayolsuz denendi ve bildirimler BOŞ geldi: Android 11'den
           beri sohbet biçimi geçerli bir kısayola bağlı olmak zorunda.
           Burada kısayol da kuruluyor. Yine de bir aksilik olursa sade
           bildirime dönülür — kullanıcı mesajsız kalmasın. */
        try {
            Person.Builder kisiYapici = new Person.Builder()
                    .setName(gonderen)
                    .setKey(kullanici.isEmpty() ? gonderen : kullanici)
                    .setBot(false);
            if (avatar != null) {
                kisiYapici.setIcon(IconCompat.createWithBitmap(avatar));
            }
            Person kisi = kisiYapici.build();

            ShortcutInfoCompat kisayol = sohbetKisayolu(konusma, kullanici, gonderen, avatar, kisi);

            /* SOHBET GEÇMİŞİ
               Aynı kişiden gelen son mesajlar bildirimde alt alta
               görünür — WhatsApp'taki gibi. Önceden yalnızca son
               mesaj gösteriliyordu, önceki mesajlar kayboluyordu. */
            String gecmisAnahtar = (kisayol != null) ? kisayol.getId() : ("klipsy_conv_" + konusma);
            gecmiseEkle(gecmisAnahtar, metin);

            NotificationCompat.MessagingStyle stil =
                    new NotificationCompat.MessagingStyle(kisi);
            stil.setConversationTitle(gonderen);

            java.util.List<String[]> gecmis = gecmisiOku(gecmisAnahtar);
            for (String[] kayit : gecmis) {
                long zaman;
                try { zaman = Long.parseLong(kayit[1]); }
                catch (Exception e) { zaman = System.currentTimeMillis(); }
                stil.addMessage(kayit[0], zaman, kisi);
            }

            NotificationCompat.Builder yapici =
                    new NotificationCompat.Builder(this, KANAL_MESAJ)
                            .setSmallIcon(uygulamaSimgesi())
                            .setColor(RENK)
                            .setContentTitle(gonderen)
                            .setContentText(metin)
                            .setStyle(stil)
                            .setContentIntent(acmaBekleyen)
                            .setAutoCancel(true)
                            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                            .setPriority(NotificationCompat.PRIORITY_HIGH)
                            .setDefaults(NotificationCompat.DEFAULT_ALL)
                            .addAction(yanitEylemi)
                            .addAction(sessizEylemi);

            if (avatar != null) yapici.setLargeIcon(avatar);
            /* setShortcutInfo — belge bunu öneriyor: uygun LocusId'yi
               kendiliğinden ekliyor, ayrıca elle vermeye gerek kalmıyor. */
            if (kisayol != null) yapici.setShortcutInfo(kisayol);

            gonder(bildirimId, yapici);
            return;

        } catch (Throwable t) {
            izBirak("sohbet biçimi kurulamadı: " + t.getClass().getSimpleName());
        }

        /* ── YEDEK: sade bildirim ── */
        NotificationCompat.Builder sade =
                new NotificationCompat.Builder(this, KANAL_MESAJ)
                        .setSmallIcon(uygulamaSimgesi())
                        .setColor(RENK)
                        .setContentTitle(gonderen)
                        .setContentText(metin)
                        .setStyle(new NotificationCompat.BigTextStyle().bigText(metin))
                        .setContentIntent(acmaBekleyen)
                        .setAutoCancel(true)
                        .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .setDefaults(NotificationCompat.DEFAULT_ALL)
                        .addAction(yanitEylemi)
                        .addAction(sessizEylemi);
        if (avatar != null) sade.setLargeIcon(avatar);
        gonder(bildirimId, sade);
    }

    /* ═══ SOHBET GEÇMİŞİ ═══
       Bildirimde son mesajları gösterebilmek için cihaz belleğinde
       tutulur. En fazla altı mesaj; eskiler düşer. Bildirim
       kapatılınca temizlenir (uygulama açılınca zaten okunmuş olur). */
    private static final int GECMIS_SINIR = 6;

    private void gecmiseEkle(String anahtar, String metin) {
        try {
            android.content.SharedPreferences ayar =
                    getSharedPreferences("KlipsySohbetGecmisi", Context.MODE_PRIVATE);
            String eski = ayar.getString(anahtar, "");

            /* Biçim: metin \u0001 zaman \u0002 metin \u0001 zaman ... */
            String yeni = metin.replace("\u0001", " ").replace("\u0002", " ")
                        + "\u0001" + System.currentTimeMillis();

            String hepsi = eski.isEmpty() ? yeni : (eski + "\u0002" + yeni);

            String[] parcalar = hepsi.split("\u0002");
            if (parcalar.length > GECMIS_SINIR) {
                StringBuilder sb = new StringBuilder();
                for (int i = parcalar.length - GECMIS_SINIR; i < parcalar.length; i++) {
                    if (sb.length() > 0) sb.append("\u0002");
                    sb.append(parcalar[i]);
                }
                hepsi = sb.toString();
            }

            ayar.edit().putString(anahtar, hepsi).apply();
        } catch (Throwable t) { }
    }

    private java.util.List<String[]> gecmisiOku(String anahtar) {
        java.util.List<String[]> liste = new java.util.ArrayList<>();
        try {
            android.content.SharedPreferences ayar =
                    getSharedPreferences("KlipsySohbetGecmisi", Context.MODE_PRIVATE);
            String hepsi = ayar.getString(anahtar, "");
            if (hepsi.isEmpty()) return liste;

            for (String parca : hepsi.split("\u0002")) {
                String[] ikili = parca.split("\u0001");
                if (ikili.length >= 2) liste.add(new String[]{ ikili[0], ikili[1] });
                else if (ikili.length == 1) {
                    liste.add(new String[]{ ikili[0], String.valueOf(System.currentTimeMillis()) });
                }
            }
        } catch (Throwable t) { }
        return liste;
    }

    /* SOHBET KISAYOLU — sohbet biçimi için ŞART.
       Android 11'den beri bu bildirimler geçerli ve uzun ömürlü bir
       kısayola bağlı olmak zorunda; bağlı değilse bildirim hiçbir
       yere düşmüyor (sesi geliyor ama görünmüyor). */
    private ShortcutInfoCompat sohbetKisayolu(String konusma, String kullanici,
                                              String gorunenAd, Bitmap avatar, Person kisi) {
        /* Kimlik KONUŞMAYA göre. Kullanıcı adı değişebiliyor;
           konuşma kimliği sabit kalıyor. */
        String temel = (konusma != null && !konusma.trim().isEmpty())
                ? konusma
                : ((kullanici == null || kullanici.isEmpty()) ? "genel" : kullanici);
        String kisayolId = "klipsy_conv_" + temel;
        try {
            Intent hedef = new Intent(Intent.ACTION_VIEW);
            hedef.setPackage(getPackageName());
            hedef.putExtra("klipsy_kind", "message");
            hedef.putExtra("klipsy_who", kullanici == null ? "" : kullanici);

            IconCompat simge = (avatar != null)
                    ? IconCompat.createWithBitmap(avatar)
                    : IconCompat.createWithResource(this, uygulamaSimgesi());

            ShortcutInfoCompat.Builder yapici = new ShortcutInfoCompat.Builder(this, kisayolId)
                    .setLongLived(true)
                    .setShortLabel(gorunenAd)
                    .setLongLabel(gorunenAd)
                    .setIcon(simge)
                    .setPerson(kisi)
                    .setIntent(hedef);

            /* LocusId — belge önemle tavsiye ediyor.
               Sistem sohbetleri sıralarken ve son etkileşim zamanını
               belirlerken bunu kullanıyor. */
            try { yapici.setLocusId(new LocusIdCompat(kisayolId)); } catch (Throwable t) { }

            /* Android 12: bunun bir sohbet olduğunu bildir. */
            try { yapici.setIsConversation(); } catch (Throwable t) { }

            ShortcutInfoCompat kisayol = yapici.build();
            ShortcutManagerCompat.pushDynamicShortcut(this, kisayol);
            return kisayol;
        } catch (Throwable t) {
            return null;
        }
    }

    /* ── Beğeni, yorum, takip
         Xiaomi/HyperOS standart kartta largeIcon SAĞA gider,
         soldaki daire uygulama ikonu olarak kilitlenir.
         Fotoğrafı sola almak için mesajdaki gibi Person ikonu
         kullanılır (MessagingStyle). İkon olarak anın kapağı
         konur — ekrandaki sağ görsel sola geçer. */
    private void genelBildirim(Map<String, String> veri) {
        String baslikHam   = deger(veri, "title", "Klipsy");
        String metinHam    = deger(veri, "body",  "");
        String tur         = deger(veri, "kind",  "");
        String anId        = deger(veri, "moment_id", "");
        String gorselAdres = deger(veri, "image", "");
        String avatarAdres = deger(veri, "avatar", "");
        String kimAdi      = deger(veri, "actor", "");

        /* Görünen ad mesajdaki gibi title'dan gelir.
           actor kullanıcı adıdır (yusufum); title ise Yusuf Korkmaz.
           name / actor_name / display_name varsa onlar tercih edilir. */
        String gorunenAd = deger(veri, "name", "");
        if (gorunenAd.trim().isEmpty()) gorunenAd = deger(veri, "actor_name", "");
        if (gorunenAd.trim().isEmpty()) gorunenAd = deger(veri, "display_name", "");
        if (gorunenAd.trim().isEmpty()) gorunenAd = deger(veri, "full_name", "");
        if (gorunenAd.trim().isEmpty()) gorunenAd = baslikHam;
        if (gorunenAd.trim().isEmpty()) gorunenAd = kimAdi;
        if (gorunenAd.trim().isEmpty()) gorunenAd = "Klipsy";

        String baslik = gorunenAd.trim();
        String metin  = metinHam.trim();
        if (metin.isEmpty()) {
            metin = baslikHam;
        }
        /* Title "Yusuf Korkmaz anını beğendi" ise adı ve eylemi ayır. */
        if (!baslik.isEmpty() && metin.equals(baslikHam) && baslikHam.startsWith(baslik)
                && baslikHam.length() > baslik.length()) {
            String kalan = baslikHam.substring(baslik.length()).trim();
            if (!kalan.isEmpty()) metin = kalan;
        }
        if (!baslik.isEmpty() && metin.startsWith(baslik)) {
            String kalan = metin.substring(baslik.length()).trim();
            if (!kalan.isEmpty()) metin = kalan;
        }
        /* Title eylem cümlesiyse ve actor kullanıcı adıysa title'ı
           isim gibi kullanmayalım; yine de eylem alt satırda kalsın. */
        if (baslik.equals(baslikHam) && !metinHam.isEmpty()
                && (baslik.contains("beğendi") || baslik.contains("yorum")
                    || baslik.contains("takip"))) {
            if (!kimAdi.trim().isEmpty()) baslik = kimAdi.trim();
        }
        if (metin.isEmpty()) metin = "Yeni bildirim";
        if (metin.startsWith("-") || metin.startsWith(":") || metin.startsWith("·")) {
            metin = metin.substring(1).trim();
        }

        int bildirimId = (tur + anId + baslik + metin).hashCode();
        PendingIntent acmaBekleyen = acmaNiyeti(bildirimId, tur, kimAdi, anId);

        Bitmap avatar  = yuvarlatilmisKare(gorselIndir(avatarAdres), 320, 70f);
        if (avatar == null) avatar = basHarfAvatari(baslik, "", 320);
        Bitmap anKapak = gorselIndir(gorselAdres);
        /* Solda görünecek görsel: önce anın fotoğrafı (şimdi sağda
           duran), yoksa profil. */
        Bitmap solGorsel = anKapak != null
                ? yuvarlatilmisKare(anKapak, 320, 70f)
                : avatar;

        try {
            Person.Builder kisiYapici = new Person.Builder()
                    .setName(baslik)
                    .setKey(kimAdi.isEmpty() ? baslik : kimAdi)
                    .setBot(false);
            if (solGorsel != null) {
                kisiYapici.setIcon(IconCompat.createWithBitmap(solGorsel));
            }
            Person kisi = kisiYapici.build();

            ShortcutInfoCompat kisayol = etkilesimKisayolu(tur, anId, kimAdi, baslik, solGorsel, kisi);

            NotificationCompat.MessagingStyle stil =
                    new NotificationCompat.MessagingStyle(kisi);
            stil.addMessage(metin, System.currentTimeMillis(), kisi);

            NotificationCompat.Builder yapici =
                    new NotificationCompat.Builder(this, KANAL_GENEL)
                            .setSmallIcon(uygulamaSimgesi())
                            .setColor(RENK)
                            .setContentTitle(baslik)
                            .setContentText(metin)
                            .setStyle(stil)
                            .setContentIntent(acmaBekleyen)
                            .setAutoCancel(true)
                            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                            .setGroup(GRUP_ETKILESIM);

            /* largeIcon KONULMAZ — Xiaomi onu sağa yapıştırır. */
            if (kisayol != null) yapici.setShortcutInfo(kisayol);

            gonder(bildirimId, yapici);
            yiginSatiriEkle(baslik, metin);
            ozetGuncelle();
            return;
        } catch (Throwable t) {
            izBirak("etkileşim biçimi kurulamadı: " + t.getClass().getSimpleName());
        }

        /* Yedek: eski sağ-thumbnail düzeni */
        NotificationCompat.Builder yedek = new NotificationCompat.Builder(this, KANAL_GENEL)
                .setSmallIcon(uygulamaSimgesi())
                .setColor(RENK)
                .setContentTitle(baslik)
                .setContentText(metin)
                .setContentIntent(acmaBekleyen)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setGroup(GRUP_ETKILESIM);
        if (solGorsel != null) yedek.setLargeIcon(solGorsel);
        if (anKapak != null) {
            yedek.setStyle(new NotificationCompat.BigPictureStyle()
                    .bigPicture(anKapak)
                    .bigLargeIcon((Bitmap) null)
                    .setBigContentTitle(baslik)
                    .setSummaryText(metin));
        }
        gonder(bildirimId, yedek);
        yiginSatiriEkle(baslik, metin);
        ozetGuncelle();
    }

    /* Beğeni/yorum kartının solda fotoğraf göstermesi için
       Android 11+ geçerli bir kısayol ister. Mesaj kısayollarından
       ayrı tutulur; sohbet listesine karışmasın. */
    private ShortcutInfoCompat etkilesimKisayolu(String tur, String anId,
                                                String kullanici, String gorunenAd,
                                                Bitmap gorsel, Person kisi) {
        String temel = (anId != null && !anId.trim().isEmpty())
                ? (tur + "_" + anId)
                : (tur + "_" + (kullanici == null || kullanici.isEmpty() ? gorunenAd : kullanici));
        String kisayolId = "klipsy_etkilesim_" + temel;
        try {
            Intent hedef = new Intent(Intent.ACTION_VIEW);
            hedef.setPackage(getPackageName());
            hedef.putExtra("klipsy_kind", tur == null ? "" : tur);
            hedef.putExtra("klipsy_who", kullanici == null ? "" : kullanici);
            hedef.putExtra("klipsy_moment", anId == null ? "" : anId);

            IconCompat simge = (gorsel != null)
                    ? IconCompat.createWithBitmap(gorsel)
                    : IconCompat.createWithResource(this, uygulamaSimgesi());

            ShortcutInfoCompat.Builder yapici = new ShortcutInfoCompat.Builder(this, kisayolId)
                    .setLongLived(true)
                    .setShortLabel(gorunenAd)
                    .setLongLabel(gorunenAd)
                    .setIcon(simge)
                    .setPerson(kisi)
                    .setIntent(hedef);
            try { yapici.setLocusId(new LocusIdCompat(kisayolId)); } catch (Throwable t) { }

            ShortcutInfoCompat kisayol = yapici.build();
            ShortcutManagerCompat.pushDynamicShortcut(this, kisayol);
            return kisayol;
        } catch (Throwable t) {
            return null;
        }
    }

    /* Açılınca görünecek satırı listeye ekler (en fazla 6 satır). */
    private void yiginSatiriEkle(String kim, String olay) {
        synchronized (yiginSatirlari) {
            yiginSatirlari.addFirst(kim + " " + olay);
            while (yiginSatirlari.size() > 6) yiginSatirlari.removeLast();
        }
    }

    /* ÖZET BİLDİRİMİ
       Kapalıyken görünen karttır. Android, gruplanmış bildirimleri
       yalnızca bir özet varsa tek kartta topluyor. */
    private void ozetGuncelle() {
        try {
            int adet;
            NotificationCompat.InboxStyle stil = new NotificationCompat.InboxStyle();

            synchronized (yiginSatirlari) {
                adet = yiginSatirlari.size();
                for (String satir : yiginSatirlari) stil.addLine(satir);
            }

            String baslik = (adet <= 1) ? "Klipsy" : (adet + " yeni bildirim");
            stil.setBigContentTitle(baslik);
            stil.setSummaryText("Klipsy");

            Intent niyet = getPackageManager().getLaunchIntentForPackage(getPackageName());
            if (niyet == null) niyet = new Intent();
            niyet.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
            niyet.putExtra("klipsy_kind", "notif");

            int bayrak = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                bayrak |= PendingIntent.FLAG_IMMUTABLE;
            }
            PendingIntent bekleyen = PendingIntent.getActivity(this, OZET_ID, niyet, bayrak);

            NotificationCompat.Builder ozet = new NotificationCompat.Builder(this, KANAL_GENEL)
                    .setSmallIcon(uygulamaSimgesi())
                    .setColor(RENK)
                    .setContentTitle(baslik)
                    .setContentIntent(bekleyen)
                    .setStyle(stil)
                    .setGroup(GRUP_ETKILESIM)
                    .setGroupSummary(true)          // bu kart özettir
                    .setAutoCancel(true);

            gonder(OZET_ID, ozet);
        } catch (Throwable ignored) { }
    }

    /* ── Yardımcılar ── */

    private PendingIntent acmaNiyeti(int id, String tur, String kim, String anId) {
        Intent niyet = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (niyet == null) niyet = new Intent();
        niyet.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        niyet.putExtra("klipsy_kind", tur);
        niyet.putExtra("klipsy_who", kim);
        niyet.putExtra("klipsy_moment", anId);

        int bayrak = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            bayrak |= PendingIntent.FLAG_IMMUTABLE;
        }
        return PendingIntent.getActivity(this, id, niyet, bayrak);
    }


    /* ═══ BAŞ HARF AVATARI ═══
       Profil fotoğrafı olmayan kullanıcı için renkli daire ve adın
       ilk harfi. Uygulamadaki avatarların bildirimdeki karşılığı.
       Renk kullanıcı adından hesaplanır: aynı kişi hep aynı rengi
       alır, rastgele değişmez. */
    private Bitmap basHarfAvatari(String gorunenAd, String kullanici, int boyut) {
        try {
            String kaynak = (gorunenAd == null || gorunenAd.trim().isEmpty())
                    ? kullanici : gorunenAd;
            if (kaynak == null) kaynak = "";
            kaynak = kaynak.trim();

            String harf = kaynak.isEmpty()
                    ? "?"
                    : kaynak.substring(0, 1).toUpperCase(new java.util.Locale("tr", "TR"));

            String anahtar = (kullanici == null || kullanici.isEmpty()) ? kaynak : kullanici;
            int h = 0;
            for (int i = 0; i < anahtar.length(); i++) {
                h = anahtar.charAt(i) + ((h << 5) - h);
            }

            int[] renkler = {
                0xFF6BBF8A, 0xFFFF7BA9, 0xFF6B8FBF, 0xFFFFC857,
                0xFF9A7AB0, 0xFF5FB6C4, 0xFFC79A6B, 0xFFFF6B35,
            };
            int renk = renkler[Math.abs(h) % renkler.length];

            Bitmap bmp = Bitmap.createBitmap(boyut, boyut, Bitmap.Config.ARGB_8888);
            Canvas tuval = new Canvas(bmp);

            Paint zemin = new Paint(Paint.ANTI_ALIAS_FLAG);
            zemin.setColor(renk);
            tuval.drawCircle(boyut / 2f, boyut / 2f, boyut / 2f, zemin);

            Paint yazi = new Paint(Paint.ANTI_ALIAS_FLAG);
            yazi.setColor(0xFFFFFFFF);
            yazi.setTextSize(boyut * 0.44f);
            yazi.setTextAlign(Paint.Align.CENTER);
            yazi.setFakeBoldText(true);

            Paint.FontMetrics fm = yazi.getFontMetrics();
            float y = boyut / 2f - (fm.ascent + fm.descent) / 2f;
            tuval.drawText(harf, boyut / 2f, y, yazi);

            return bmp;
        } catch (Throwable t) {
            return null;
        }
    }

    private void gonder(int id, NotificationCompat.Builder yapici) {
        try {
            NotificationManagerCompat.from(this).notify(id, yapici.build());
            izBirak("gösterildi id=" + id);
        } catch (SecurityException e) {
            izBirak("İZİN YOK — bildirim gösterilemedi");
        } catch (Throwable t) {
            izBirak("HATA: " + t.getClass().getSimpleName());
        }
    }

    /* Görseli indir. Bildirim servisinde kısa ağ işlemi yapılabilir. */
    private Bitmap gorselIndir(String adres) {
        if (adres == null || adres.isEmpty()) return null;
        InputStream akis = null;
        try {
            URLConnection baglanti = new URL(adres).openConnection();
            baglanti.setConnectTimeout(5000);
            baglanti.setReadTimeout(5000);
            akis = baglanti.getInputStream();

            /* Ölçek düşürme KAPALI: varsayılan ayarlarla görsel
               cihaz yoğunluğuna göre küçültülebiliyor ve bildirimde
               bulanık görünüyordu. */
            BitmapFactory.Options ayar = new BitmapFactory.Options();
            ayar.inScaled = false;
            ayar.inPreferredConfig = Bitmap.Config.ARGB_8888;
            return BitmapFactory.decodeStream(akis, null, ayar);
        } catch (Exception e) {
            return null;
        } finally {
            if (akis != null) {
                try { akis.close(); } catch (Exception ignored) { }
            }
        }
    }

    /* Görseli YUVARLATILMIŞ KARE biçimine getirir.
       Android, kişi simgelerini daire olarak kırpıyor; largeIcon ise
       verdiğimiz biçimi koruyor. Bu yüzden kare köşeli yumuşatılmış
       bir görsel üretip largeIcon olarak veriyoruz. */
    private Bitmap yuvarlatilmisKare(Bitmap kaynak, int boyut, float koseYaricap) {
        if (kaynak == null) return null;
        try {
            // ortadan kare kırp
            int k = Math.min(kaynak.getWidth(), kaynak.getHeight());
            int x = (kaynak.getWidth() - k) / 2;
            int y = (kaynak.getHeight() - k) / 2;
            Bitmap kare = Bitmap.createBitmap(kaynak, x, y, k, k);
            Bitmap olcekli = Bitmap.createScaledBitmap(kare, boyut, boyut, true);

            Bitmap sonuc = Bitmap.createBitmap(boyut, boyut, Bitmap.Config.ARGB_8888);
            android.graphics.Canvas tuval = new android.graphics.Canvas(sonuc);
            android.graphics.Paint firca = new android.graphics.Paint();
            firca.setAntiAlias(true);

            android.graphics.RectF alan = new android.graphics.RectF(0, 0, boyut, boyut);
            tuval.drawRoundRect(alan, koseYaricap, koseYaricap, firca);

            firca.setXfermode(new android.graphics.PorterDuffXfermode(
                    android.graphics.PorterDuff.Mode.SRC_IN));
            tuval.drawBitmap(olcekli, 0, 0, firca);

            return sonuc;
        } catch (Exception e) {
            return kaynak;
        }
    }

    private String deger(Map<String, String> m, String anahtar, String varsayilan) {
        if (m == null) return varsayilan;
        String v = m.get(anahtar);
        return (v == null) ? varsayilan : v;
    }

    private void kanallariKur() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;

        NotificationManager yonetici =
                (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (yonetici == null) return;

        /* Eski kanalı SİL. Ayarları düşük kaldığı için bildirim
           görünmüyordu; kanal ayarı sonradan yükseltilemiyor. */
        try { yonetici.deleteNotificationChannel(KANAL_MESAJ_ESKI); }
        catch (Throwable ignored) { }

        NotificationChannel mesajKanali = new NotificationChannel(
                KANAL_MESAJ, "Mesajlar", NotificationManager.IMPORTANCE_HIGH);
        mesajKanali.setDescription("Klipsy özel mesajları");
        mesajKanali.enableVibration(true);
        mesajKanali.enableLights(true);
        mesajKanali.setLightColor(RENK);
        mesajKanali.setShowBadge(true);
        mesajKanali.setLockscreenVisibility(
                android.app.Notification.VISIBILITY_PRIVATE);

        android.media.AudioAttributes ses = new android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();
        mesajKanali.setSound(
                android.provider.Settings.System.DEFAULT_NOTIFICATION_URI, ses);

        NotificationChannel genelKanal = new NotificationChannel(
                KANAL_GENEL, "Klipsy", NotificationManager.IMPORTANCE_DEFAULT);
        genelKanal.setDescription("Beğeni, yorum, takip");
        genelKanal.enableVibration(true);

        yonetici.createNotificationChannel(mesajKanali);
        yonetici.createNotificationChannel(genelKanal);
    }
}
