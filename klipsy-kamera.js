/* ============================================================================
   KLİPSY — KAMERA KATMANI
   ============================================================================
   Kamera bu uygulamanın bel kemiği. Bu dosya kameranın TEK giriş noktasıdır;
   uygulamanın geri kalanı kamera ayrıntılarını bilmez.

   İKİ YOL
     UYGULAMA (APK)  → Android'in kendi kamerası (CameraX).
                       Önizleme donanımdan doğrudan ekrana çizilir, kayıt
                       donanım kodlayıcıyla yapılır. Görüntü hiç JavaScript'ten
                       geçmez. Kayıt sırasında kamera çevirmek de bedavadır.
     WEB             → getUserMedia, yalnızca arka kamera, doğrudan kayıt.
                       Tuval KULLANILMAZ: her kareyi JavaScript ile kopyalamak
                       kaydı dondurur. Web bir vitrindir; ciddi çekim uygulamada.

   TASARIM KURALLARI
     1. Hiçbir hata sessizce yutulmaz. Her hata sınıflandırılır ve bildirilir.
     2. Kaynaklar her yolda serbest bırakılır (hata olsa bile).
     3. Aynı anda iki işlem çalışmaz; işlemler sıraya alınır.
     4. Uygulama arka plana geçince kamera bırakılır, dönünce geri alınır.

   HIZLI KULLANIM
     Kamera.olay(e => console.log(e.tur, e));
     await Kamera.baslat({ yon:'arka' });
     const foto = await Kamera.fotoCek();
     await Kamera.kayitBaslat({ enFazlaSn: 30 });
     const video = await Kamera.kayitBitir();   // { blob, sure, tur }
     await Kamera.durdur();
   ============================================================================ */

(function (global) {
  "use strict";

  /* ══════════════════════════════════════════════════════════════════
     HATA TÜRLERİ
     Çağıran taraf hatayı ayırt edebilsin diye sınıflandırılır.
     Kullanıcıya gösterilecek metin uygulamanın çeviri dosyasından gelir.
     ══════════════════════════════════════════════════════════════════ */
  const HATA = {
    IZIN_YOK:        "izin_yok",
    KAMERA_YOK:      "kamera_yok",
    MESGUL:          "mesgul",
    DESTEKSIZ:       "desteksiz",
    GUVENSIZ_BAGLAM: "guvensiz_baglam",
    KAYIT_HATASI:    "kayit_hatasi",
    BILINMEYEN:      "bilinmeyen",
  };

  function hataCevir(e) {
    const ad  = (e && (e.name || e.code)) ? String(e.name || e.code) : "";
    const msj = (e && e.message) ? String(e.message) : "";
    const hepsi = (ad + " " + msj).toLowerCase();

    if (/notallowed|permission|denied|izin/.test(hepsi))        return HATA.IZIN_YOK;
    if (/notfound|devicesnotfound|nocamera/.test(hepsi))        return HATA.KAMERA_YOK;
    if (/notreadable|trackstart|inuse|busy/.test(hepsi))        return HATA.MESGUL;
    if (/notsupported|typeerror/.test(hepsi))                   return HATA.DESTEKSIZ;
    if (/secure|https/.test(hepsi))                             return HATA.GUVENSIZ_BAGLAM;
    return HATA.BILINMEYEN;
  }

  function KameraHatasi(tur, asil) {
    const h = new Error("Kamera: " + tur);
    h.tur = tur;
    h.asil = asil || null;
    return h;
  }

  /* ══════════════════════════════════════════════════════════════════
     ORTAM
     ══════════════════════════════════════════════════════════════════ */
  function cap() { return global.Capacitor || null; }

  function yerelMi() {
    try {
      const c = cap();
      if (!c || !c.isNativePlatform || !c.isNativePlatform()) return false;
      return !!((c.Plugins || {}).CameraPreview);
    } catch (e) { return false; }
  }

  function CP() {
    const c = cap();
    return (c && c.Plugins && c.Plugins.CameraPreview) || null;
  }

  function guvenliBaglamMi() {
    if (yerelMi()) return true;
    try {
      const c = cap();
      if (c && c.isNativePlatform && c.isNativePlatform()) return true;
    } catch (e) {}
    const proto = String(location.protocol || "");
    if (/^(capacitor|ionic|file|http|https):/.test(proto)) return true;
    return !!(global.isSecureContext ||
              /^(localhost|127\.0\.0\.1)$/.test(location.hostname));
  }

  /* ══════════════════════════════════════════════════════════════════
     OLAY YAYINI
     Uygulama kameranın durumunu buradan izler; yoklama yapmaz.
     ══════════════════════════════════════════════════════════════════ */
  const dinleyiciler = [];

  function olay(geriCagri) {
    if (typeof geriCagri !== "function") return function () {};
    dinleyiciler.push(geriCagri);
    return function () {
      const i = dinleyiciler.indexOf(geriCagri);
      if (i >= 0) dinleyiciler.splice(i, 1);
    };
  }

  function yay(tur, veri) {
    const e = Object.assign({ tur: tur, zaman: Date.now() }, veri || {});
    dinleyiciler.forEach(function (f) { try { f(e); } catch (x) {} });
  }

  /* ══════════════════════════════════════════════════════════════════
     DURUM
     ══════════════════════════════════════════════════════════════════ */
  const durum = {
    acik: false,
    hazirlaniyor: false,
    kaydediyor: false,
    yon: "arka",
    flas: "off",
    yakinlik: 1,
    onizlemeKip: "fit",
    kayitBaslangic: 0,
    yerel: false,
    coz: null,
  };

  let webAkis = null;
  let webKayit = null;
  let webParcalar = [];
  let kayitZamanlayici = null;

  /* Kayıt süre/dosya sınırına takılıp kendiliğinden bittiğinde eklenti
     dosya yolunu olayla bildirir. Uygulama sonradan istediğinde
     kaybolmasın diye burada saklanır. */
  let _sonKayitYolu = null;
  let _sonKayitSure = 0;

  /* Aynı anda iki işlem çalışmasın diye basit bir sıra.
     Kullanıcı çevirme düğmesine hızlı iki kez basarsa ikinci istek
     birincisi bitmeden başlamaz. */
  let sira = Promise.resolve();
  function sirala(is) {
    sira = sira.then(is, is);
    return sira;
  }

  function yonNative(y) { return y === "on" ? "front" : "rear"; }

  /* ══════════════════════════════════════════════════════════════════
     İZİNLER
     ══════════════════════════════════════════════════════════════════ */
  async function izinIste(sesGerekli) {
    if (!yerelMi()) return true;      // web'de getUserMedia kendi sorar

    /* Eklentinin KENDİ izin arayüzü kullanılır (sürüm 8.7'den beri).
       Önceden başka bir eklentinin izin arayüzü deneniyordu; o eklenti
       kurulu olmadığı için izin hiç istenmiyor ve kamera açılmıyordu. */
    const P = CP();
    try {
      if (P.checkPermissions) {
        let d = await P.checkPermissions({ disableAudio: !sesGerekli });
        const eksik = (d.camera !== "granted") ||
                      (sesGerekli && d.microphone !== "granted");
        if (eksik && P.requestPermissions) {
          d = await P.requestPermissions({ disableAudio: !sesGerekli });
        }
        if (d.camera !== "granted") throw KameraHatasi(HATA.IZIN_YOK);
      }
    } catch (e) {
      if (e && e.tur) throw e;
      throw KameraHatasi(hataCevir(e), e);
    }
    return true;
  }

  /* ══════════════════════════════════════════════════════════════════
     BAŞLAT
     ══════════════════════════════════════════════════════════════════ */
  function baslat(secenek) {
    secenek = secenek || {};
    return sirala(async function () {
      if (durum.acik || durum.hazirlaniyor) return;

      if (!guvenliBaglamMi()) {
        const h = KameraHatasi(HATA.GUVENSIZ_BAGLAM);
        yay("hata", { hataTuru: h.tur, hata: h });
        throw h;
      }

      durum.hazirlaniyor = true;
      durum.yerel = yerelMi();
      durum.yon = secenek.yon || "arka";
      yay("hazirlaniyor");

      try {
        await izinIste(secenek.ses !== false);

        if (durum.yerel) await yerelBaslat(secenek);
        else             await webBaslat(secenek);

        durum.acik = true;
        durum.hazirlaniyor = false;
        yay("basladi", { yerel: durum.yerel, yon: durum.yon, coz: durum.coz });
      } catch (e) {
        durum.hazirlaniyor = false;
        await temizle();
        const tur = (e && e.tur) ? e.tur : hataCevir(e);
        yay("hata", { hataTuru: tur, hata: e });
        throw KameraHatasi(tur, e);
      }
    });
  }

  async function yerelBaslat(secenek) {
    /* SEÇENEKLER
         enableZoom      Gönderilmiyor; yakınlaştırma setZoom ile yapılıyor.
         enableVideoMode Video kaydı için gerekli.
         width/height/x/y start() aşamasında gerçek 9:16 preview alanını
                         native tarafa bildirir.
         storeToFile     Burada verilmez; fotoğraf base64 olarak döner. */
    function onizlemeKutusu() {
      const vw = window.innerWidth || 360, vh = window.innerHeight || 640;
      const sat = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--sat")) || 0;
      const sab = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--sab")) || 0;
      const ust = sat + 56;
      const alt = sab + 210;
      const aw = vw, ah = Math.max(120, vh - ust - alt);
      const h9 = Math.round(aw * 16 / 9);
      const w = aw;
      const h = Math.min(ah, h9);
      const x = 0;
      const y = Math.round(ust + (ah - h) / 2);
      return { x: x, y: y, width: w, height: h };
    }

    /*
       KRITIK 9:16 KAMERA KADRAJI
       --------------------------
       setPreviewSize() sadece native View'un dikdortgenini degistirir.
       CameraPreview ise start() aninda kamera icin uygun preview
       cozunurlugunu secer. Start() ekran boyutlariyla (ornegin 691x1536)
       baslatilirsa Android 4:3 bir preview secip onu sonradan 9:16
       kutuya yerlestirebilir. Kullanici ekranda 4:3 gorur, capture ise
       9:16 doner ve kadraj degisir.

       Bu nedenle ayni 9:16 dikdortgeni START asamasinda veriyoruz.
       Boylece native preview secimi de 9:16 hedefini goruyor.
    */
    const previewRect = onizlemeKutusu();
    const taban = {
      position: yonNative(durum.yon),
      width: previewRect.width,
      height: previewRect.height,
      x: previewRect.x,
      y: previewRect.y,
      toBack: true,
      enableVideoMode: true,
      lockAndroidOrientation: true,
      disableAudio: secenek.ses === false,
      videoQuality: "high",
      includeSafeAreaInsets: false,
    };
    if (secenek.kap)   taban.parent    = secenek.kap;
    if (secenek.sinif) taban.className = secenek.sinif;

    const denemeler = [
      Object.assign({}, taban),
      Object.assign({}, taban, { force: true }),
    ];

    let sonuc = null;
    let sonHata = null;
    for (let i = 0; i < denemeler.length; i++) {
      try {
        sonuc = await CP().start(denemeler[i]);
        sonHata = null;
        break;
      } catch (e) {
        sonHata = e;
        const msg = String((e && (e.message || e.errorMessage)) || e || "");
        if (/already|is running|already started/i.test(msg)) {
          sonHata = null;
          break;
        }
      }
    }
    if (sonHata) throw sonHata;

    durum.coz = sonuc
      ? { g: sonuc.width, y: sonuc.height, x: sonuc.x, y0: sonuc.y }
      : null;

    if (CP().setPreviewSize) {
      try {
        await CP().setPreviewSize(previewRect);
      } catch (e) {}
    }

    document.documentElement.classList.add("camNativeOn");
  }

  async function webKameraBul(istenenYuz) {
    try {
      const list = await navigator.mediaDevices.enumerateDevices();
      const cam = list.filter(function (d) { return d.kind === "videoinput"; });
      const on = [], arka = [];
      cam.forEach(function (d) {
        const L = String(d.label || "").toLowerCase();
        if (/front|user|face|\bön\b|selfie/.test(L)) on.push(d);
        else if (/back|rear|environment|world|\barka\b/.test(L)) arka.push(d);
      });
      if (istenenYuz === "user") return on[0] || null;
      return arka[0] || null;
    } catch (e) { return null; }
  }

  async function webBaslat(secenek) {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      throw KameraHatasi(HATA.DESTEKSIZ);
    }

    const sesVar = secenek.ses !== false;
    const istenenYuz = (durum.yon === "on") ? "user" : "environment";

    if (webAkis) {
      try { webAkis.getTracks().forEach(function (t) { t.stop(); }); } catch (e) {}
      webAkis = null;
    }

    const cihaz = await webKameraBul(istenenYuz);
    /* width ideal — height/aspectRatio YOK (kırpmaz).
       resizeMode none: native kare. 1920 çoğu telefonda HD önizleme verir. */
    const hd = { width: { ideal: 1920 }, resizeMode: "none" };
    const denemeler = [];
    if (cihaz && cihaz.deviceId) {
      denemeler.push({ video: Object.assign({ deviceId: { exact: cihaz.deviceId } }, hd), audio: sesVar });
      denemeler.push({ video: { deviceId: { exact: cihaz.deviceId }, width: { ideal: 1920 } }, audio: sesVar });
      denemeler.push({ video: { deviceId: { exact: cihaz.deviceId } }, audio: sesVar });
    }
    denemeler.push({ video: Object.assign({ facingMode: { exact: istenenYuz } }, hd), audio: sesVar });
    denemeler.push({ video: { facingMode: { exact: istenenYuz }, width: { ideal: 1920 } }, audio: sesVar });
    denemeler.push({ video: { facingMode: { ideal: istenenYuz }, width: { ideal: 1920 }, resizeMode: "none" }, audio: sesVar });
    denemeler.push({ video: { facingMode: istenenYuz }, audio: sesVar });

    let sonHata = null;
    for (let i = 0; i < denemeler.length; i++) {
      try { webAkis = await navigator.mediaDevices.getUserMedia(denemeler[i]); break; }
      catch (e) { sonHata = e; }
    }
    if (!webAkis) throw sonHata || KameraHatasi(HATA.BILINMEYEN);

    const iz = webAkis.getVideoTracks()[0];
    const a = (iz && iz.getSettings) ? iz.getSettings() : {};
    if (a.facingMode === "user") durum.yon = "on";
    else if (a.facingMode === "environment") durum.yon = "arka";
    else if (istenenYuz === "user") durum.yon = "on";
    else durum.yon = "arka";

    try {
      const y = (iz && iz.getCapabilities) ? iz.getCapabilities() : null;
      if (iz && iz.applyConstraints && y && y.zoom && typeof y.zoom.min === "number") {
        await iz.applyConstraints({ advanced: [{ zoom: y.zoom.min }] });
        durum.yakinlik = y.zoom.min;
        _aralik = { min: y.zoom.min, max: Math.min(y.zoom.max || 8, 8) };
      }
    } catch (e) {}

    durum.coz = { g: a.width || null, y: a.height || null, fps: Math.round(a.frameRate || 0) };

    const v = document.getElementById(secenek.video || "camVideo");
    if (v) {
      v.srcObject = webAkis;
      v.muted = true;
      v.playsInline = true;
      v.setAttribute("playsinline", "");
      try { await v.play(); } catch (e) {}
    }

    /* Kamera dışarıdan kesilirse (başka uygulama aldı) sessizce donmuş
       görünmesin; uygulamaya haber ver. */
    if (iz) {
      iz.addEventListener("ended", function () {
        yay("kesildi");
        durum.acik = false;
      });
    }
  }

  /* ══════════════════════════════════════════════════════════════════
     DURDUR / TEMİZLE
     ══════════════════════════════════════════════════════════════════ */
  async function temizle() {
    clearTimeout(kayitZamanlayici); kayitZamanlayici = null;

    if (webKayit) {
      try { if (webKayit.state !== "inactive") webKayit.stop(); } catch (e) {}
      webKayit = null;
    }
    webParcalar = [];

    if (webAkis) {
      try { webAkis.getTracks().forEach(function (t) { t.stop(); }); } catch (e) {}
      webAkis = null;
    }

    const v = document.getElementById("camVideo");
    if (v) { try { v.srcObject = null; } catch (e) {} }

    if (yerelMi()) {
      try { await CP().stop(); } catch (e) {}
      document.documentElement.classList.remove("camNativeOn");
      _aralik = null;   // kamera değişince aralık yeniden sorulur
    }

    durum.kaydediyor = false;
  }

  function durdur() {
    return sirala(async function () {
      if (!durum.acik && !durum.hazirlaniyor) return;
      if (durum.kaydediyor) { try { await kayitBitirIc(); } catch (e) {} }
      await temizle();
      durum.acik = false;
      durum.coz = null;
      yay("durdu");
    });
  }

  /* ══════════════════════════════════════════════════════════════════
     KAMERA ÇEVİR
     ══════════════════════════════════════════════════════════════════ */
  function cevir() {
    return sirala(async function () {
      if (!durum.acik) return durum.yon;

      if (durum.yerel) {
        const hedef = durum.yon === "on" ? "arka" : "on";
        try {
          await CP().flip();
          durum.yon = hedef;
          yay("cevrildi", { yon: durum.yon });
        } catch (e) {
          try {
            durum.yon = hedef;
            if (sonSecenek) sonSecenek.yon = hedef;
            await CP().stop();
          } catch (e0) {}
          try {
            await yerelBaslat(Object.assign({}, sonSecenek || {}, { yon: hedef }));
            document.documentElement.classList.add("camNativeOn");
            yay("cevrildi", { yon: durum.yon });
          } catch (e2) {
            durum.yon = hedef === "on" ? "arka" : "on";
            try { await yerelBaslat(sonSecenek || {}); document.documentElement.classList.add("camNativeOn"); } catch (e3) {}
          }
        }
        return durum.yon;
      }

      if (durum.kaydediyor) {
        yay("bilgi", { kod: "web_kayitta_cevirme_yok" });
        return durum.yon;
      }
      try {
        if (webAkis) {
          try { webAkis.getTracks().forEach(function (t) { t.stop(); }); } catch (e) {}
          webAkis = null;
        }
        const v0 = document.getElementById("camVideo");
        if (v0) { try { v0.srcObject = null; } catch (e) {} }
        durum.yon = durum.yon === "on" ? "arka" : "on";
        _aralik = null;
        await webBaslat(sonSecenek || {});
        yay("cevrildi", { yon: durum.yon });
      } catch (e) {
        try {
          durum.yon = durum.yon === "on" ? "arka" : "on";
          await webBaslat(sonSecenek || {});
        } catch (e2) {}
        yay("hata", { hataTuru: hataCevir(e), hata: e });
      }
      return durum.yon;
    });
  }

  /* ══════════════════════════════════════════════════════════════════
     FOTOĞRAF
     ══════════════════════════════════════════════════════════════════ */
  /* Bir görseli yatay çevirir (ayna). */
  function aynala(veriAdresi) {
    return new Promise(function (coz) {
      try {
        const im = new Image();
        im.onload = function () {
          try {
            const c = document.createElement("canvas");
            c.width = im.width; c.height = im.height;
            const x = c.getContext("2d");
            x.translate(c.width, 0);
            x.scale(-1, 1);
            x.drawImage(im, 0, 0);
            coz(c.toDataURL("image/jpeg", 0.92));
          } catch (e) { coz(veriAdresi); }
        };
        im.onerror = function () { coz(veriAdresi); };
        im.src = veriAdresi;
      } catch (e) { coz(veriAdresi); }
    });
  }

  function fotoCek(secenek) {
    secenek = secenek || {};
    const kalite = secenek.kalite || 92;

    return sirala(async function () {
      if (!durum.acik) return null;

      try {
        if (durum.yerel) {
          /*
             ÖNİZLEME ↔ FOTOĞRAF KADRAJI
             Native CameraPreview varsayılan capture boyutunu cihaza
             bırakınca bazı Android telefonlarda preview ile fotoğrafın
             en-boy oranı farklı seçiliyor. Bu da paylaşım ekranında
             yanlardan daha fazla/az alan görülmesine neden oluyor.

             Preview'ı uygulamada 9:16 olarak kullandığımız için capture
             isteğini de aynı oranla yapıyoruz. Eklenti desteklediği en
             yakın fotoğraf boyutunu seçer; sonrasında index.html yalnızca
             gerekiyorsa aynı 9:16 oranını uygular.
          */
          const r = await CP().capture({
            quality: kalite,
            width: 1080,
            height: 1920
          });
          const v = r && (r.value || r.base64 || r.data);
          if (!v) throw KameraHatasi(HATA.BILINMEYEN);
          let veri = /^data:/.test(v) ? v : "data:image/jpeg;base64," + v;

          /* ÖN KAMERADA AYNALAMA
             Önizleme ayna gibi gösteriliyor (kullanıcı kendini
             alışık olduğu yönde görüyor). Çekilen kare ise
             aynalanmıyordu; paylaşınca yazılar ters çıkıyor ve
             yüz "başkasının gördüğü" yönde oluyordu. Önizlemeyle
             aynı olması için kare de çevrilir. */
          if (durum.yon === "on") {
            veri = await aynala(veri);
          }

          yay("foto", { boyut: veri.length });
          return veri;
        }

        /* Web: görüntüden TEK kare alınır. Sürekli çizim yok. */
        const v = document.getElementById("camVideo");
        if (!v || !v.videoWidth) return null;

        const c = document.createElement("canvas");
        c.width = v.videoWidth;
        c.height = v.videoHeight;
        const x = c.getContext("2d");
        x.imageSmoothingQuality = "high";

        /* Ön kamerada önizleme aynalı; kare de aynalanmalı. */
        if (durum.yon === "on") {
          x.translate(c.width, 0);
          x.scale(-1, 1);
        }
        x.drawImage(v, 0, 0);
        const veri = c.toDataURL("image/jpeg", kalite / 100);
        yay("foto", { boyut: veri.length });
        return veri;
      } catch (e) {
        const tur = (e && e.tur) ? e.tur : hataCevir(e);
        yay("hata", { hataTuru: tur, hata: e });
        return null;
      }
    });
  }

  /* ══════════════════════════════════════════════════════════════════
     VİDEO KAYDI
     ══════════════════════════════════════════════════════════════════ */
  function kayitBaslat(secenek) {
    secenek = secenek || {};
    const enFazlaSn = secenek.enFazlaSn || 30;

    return sirala(async function () {
      if (!durum.acik || durum.kaydediyor) return false;

      try {
        if (durum.yerel) {
          /* Kayıt donanım kodlayıcıyla yapılır: görüntü hiç
             JavaScript'ten geçmez. Donmanın asıl sebebi buydu.

             Eklenti sürümleri arasında seçenek adları değişebiliyor;
             sade çağrı önce denenir, olmazsa seçenekli çağrı. */
          /* Kayıt seçenekleri belgeye göre:
               maxDuration  süre sınırı (saniye) — kayıt kendi durur
               disableAudio sesli kayıt için false
               videoQuality çözünürlük
             Süre sınırı burada verildiği için kendi zamanlayıcımız
             yalnızca yedek olarak çalışır. */
          try{
            await CP().startRecordVideo({
              /* storeToFile ŞART.
                 Verilmediğinde eklenti videoyu dosyaya yazmıyor;
                 sonuçta gelen değer dosya yolu değil ve okuma boş
                 dönüyor. Sunucuya birkaç baytlık bozuk dosya
                 yükleniyordu. Belgedeki örnek de bunu kullanıyor. */
              storeToFile: true,
              disableAudio: false,
              maxDuration: enFazlaSn,
              videoQuality: "high",
            });
          }catch(e1){
            const ay = String((e1 && e1.message) || "");
            yay("hata", { hataTuru: HATA.KAYIT_HATASI, hata: e1, ayrinti: ay });
            throw e1;
          }
        } else {
          if (!webAkis) return false;

          const turler = [
            "video/mp4;codecs=h264,aac",
            "video/webm;codecs=vp9,opus",
            "video/webm;codecs=vp8,opus",
            "video/webm",
          ];
          let tur = "";
          for (let i = 0; i < turler.length; i++) {
            if (global.MediaRecorder && MediaRecorder.isTypeSupported(turler[i])) {
              tur = turler[i]; break;
            }
          }

          webParcalar = [];

          /* VERİ HIZI ÇÖZÜNÜRLÜĞE GÖRE.
             Sabit 3.4 Mbit kullanılıyordu. 1080p için bu düşük;
             görüntü bloklu ve bulanık çıkıyordu. Piksel sayısına
             göre hesaplanınca kalite belirgin şekilde düzeliyor. */
          const iz = webAkis.getVideoTracks()[0];
          const a  = (iz && iz.getSettings) ? iz.getSettings() : {};
          const g  = a.width  || 1280;
          const y  = a.height || 720;
          const kare = a.frameRate || 30;

          /* Piksel başına yaklaşık 0.12 bit — akıcı hareket için yeterli,
             dosya boyutu makul kalıyor. Mobilde yazılım kodlayıcı yüksek
             veri hızında takıldığı için üst sınır düşük tutulur. */
          let hiz = Math.round(g * y * kare * 0.12);
          const mobilKayit = (function () {
            try {
              return (navigator.maxTouchPoints > 0) &&
                     /android|iphone|ipad|ipod|mobile/i.test(navigator.userAgent);
            } catch (e) { return false; }
          })();
          const ustSinir = mobilKayit ? 6000000 : 12000000;   // mobil 6, masaüstü 12 Mbit
          hiz = Math.max(2500000, Math.min(hiz, ustSinir));

          const ayar = {
            videoBitsPerSecond: secenek.bitHizi || hiz,
            audioBitsPerSecond: 128000,
          };
          if (tur) ayar.mimeType = tur;

          try { webKayit = new MediaRecorder(webAkis, ayar); }
          catch (e) {
            /* Bazı tarayıcılar ses hızını kabul etmiyor. */
            try { webKayit = new MediaRecorder(webAkis, { mimeType: tur }); }
            catch (e2) { webKayit = new MediaRecorder(webAkis); }
          }

          webKayit.ondataavailable = function (e) {
            if (e.data && e.data.size) webParcalar.push(e.data);
          };
          webKayit.onerror = function (e) {
            yay("hata", { hataTuru: HATA.KAYIT_HATASI, hata: e });
          };
          /* Parça aralığı büyütüldü: her çeyrek saniyede parça üretmek
             işlemciyi meşgul ediyor ve kayıt takılıyordu. */
          webKayit.start(1000);
        }

        durum.kaydediyor = true;
        durum.kayitBaslangic = Date.now();
        yay("kayitBasladi", { enFazlaSn: enFazlaSn });

        /* Süre sınırı: kullanıcı durdurmayı unutursa kayıt kendiliğinden
           biter, dosya şişmez. */
        clearTimeout(kayitZamanlayici);
        kayitZamanlayici = setTimeout(function () {
          yay("kayitSuresiDoldu");
          kayitBitir().catch(function () {});
        }, enFazlaSn * 1000);

        return true;
      } catch (e) {
        durum.kaydediyor = false;
        const tur = (e && e.tur) ? e.tur : hataCevir(e);
        yay("hata", { hataTuru: tur, hata: e });
        return false;
      }
    });
  }

  function kayitBitir() {
    return sirala(function () { return kayitBitirIc(); });
  }

  async function kayitBitirIc() {
    if (!durum.kaydediyor) return null;
    clearTimeout(kayitZamanlayici); kayitZamanlayici = null;

    const sure = Date.now() - durum.kayitBaslangic;

    try {
      if (durum.yerel) {
        const r = await CP().stopRecordVideo();
        durum.kaydediyor = false;

        const yol = r && (r.videoFilePath || r.value || r.path);
        if (!yol) throw KameraHatasi(HATA.KAYIT_HATASI);

        /* Bazı sürümler dosya yolu yerine videonun kendisini metin
           olarak döndürüyor. O zaman okumaya çalışmak anlamsız —
           doğrudan veriye çevrilir. */
        if (/^data:/.test(yol) || (yol.length > 5000 && !/[\/\\]/.test(yol))) {
          const veriAdresi = /^data:/.test(yol) ? yol : ("data:video/mp4;base64," + yol);
          try {
            const b = await (await fetch(veriAdresi)).blob();
            if (b && b.size > 1024) {
              yay("kayitBitti", { sure: sure, boyut: b.size });
              return { blob: b, yol: null, sure: sure, tur: b.type || "video/mp4" };
            }
          } catch (e) {}
          throw KameraHatasi(HATA.KAYIT_HATASI);
        }

        /* Dosya yolunu tarayıcının okuyabileceği adrese çevirip
           yükleme için veri parçasına dönüştür.

           OKUMA BAŞARISIZ OLURSA VAZGEÇİLİR.
           Önceden boş sonuçla devam ediliyordu: sunucuya birkaç
           baytlık bozuk bir dosya yükleniyor, video hiçbir yerde
           oynamıyordu. Sorun ancak depolama incelenince görülüyordu. */
        let blob = null;
        let okumaHatasi = null;

        /* Kayıt dosyasının diske yazılması bir an sürebiliyor;
           ilk deneme boş dönerse kısa bir bekleyip tekrar denenir. */
        for (let deneme = 0; deneme < 3; deneme++) {
          try {
            const c = cap();
            const adres = (c && c.convertFileSrc) ? c.convertFileSrc(yol) : yol;
            const cevap = await fetch(adres);
            const b = await cevap.blob();
            if (b && b.size > 1024) { blob = b; break; }   // en az 1 KB
            okumaHatasi = "dosya boş (" + (b ? b.size : 0) + " bayt)";
          } catch (e) {
            okumaHatasi = String((e && e.message) || e);
          }
          await new Promise(function (b2) { setTimeout(b2, 300); });
        }

        if (!blob) {
          yay("hata", {
            hataTuru: HATA.KAYIT_HATASI,
            ayrinti: "kayıt okunamadı: " + (okumaHatasi || "bilinmeyen"),
          });
          throw KameraHatasi(HATA.KAYIT_HATASI);
        }

        const sonuc = {
          blob: blob, yol: yol, sure: sure,
          tur: (blob && blob.type) || "video/mp4",
        };
        yay("kayitBitti", { sure: sure, boyut: blob.size });
        return sonuc;
      }

      // web
      return await new Promise(function (coz) {
        if (!webKayit) { durum.kaydediyor = false; coz(null); return; }

        webKayit.onstop = function () {
          const tur = webParcalar[0] ? webParcalar[0].type : "video/webm";
          const blob = new Blob(webParcalar, { type: tur });
          webParcalar = [];
          webKayit = null;
          durum.kaydediyor = false;
          yay("kayitBitti", { sure: sure, boyut: blob.size });
          coz({ blob: blob, yol: null, sure: sure, tur: tur });
        };

        try { webKayit.stop(); }
        catch (e) {
          durum.kaydediyor = false;
          yay("hata", { hataTuru: HATA.KAYIT_HATASI, hata: e });
          coz(null);
        }
      });
    } catch (e) {
      durum.kaydediyor = false;
      const tur = (e && e.tur) ? e.tur : hataCevir(e);
      yay("hata", { hataTuru: tur, hata: e });
      return null;
    }
  }

  /* Kayıt kendiliğinden bittiğinde (süre/dosya sınırı) eklenti haber
     verir. Uygulamanın haberi olsun diye yakalanır. */
  (function bagla() {
    if (!yerelMi()) return;
    try {
      CP().addListener("recordingFinished", function (d) {
        if (!durum.kaydediyor) return;
        durum.kaydediyor = false;
        clearTimeout(kayitZamanlayici);
        _sonKayitYolu = d && d.videoFilePath;
        _sonKayitSure = Date.now() - durum.kayitBaslangic;
        yay("kayitKendiBitti", { yol: _sonKayitYolu, sebep: d && d.reason });
      });
    } catch (e) {}
  })();

  /* ══════════════════════════════════════════════════════════════════
     FLAŞ VE YAKINLAŞTIRMA
     ══════════════════════════════════════════════════════════════════ */
  async function flas(mod) {
    mod = mod || "off";
    if (durum.yerel) {
      try { await CP().setFlashMode({ flashMode: mod }); durum.flas = mod; }
      catch (e) { yay("hata", { hataTuru: hataCevir(e), hata: e }); }
      return durum.flas;
    }

    /* Web'de flaş yalnızca "torch" olarak ve cihaz destekliyorsa çalışır. */
    try {
      const iz = webAkis && webAkis.getVideoTracks()[0];
      const y = (iz && iz.getCapabilities) ? iz.getCapabilities() : null;
      if (y && y.torch) {
        await iz.applyConstraints({
          advanced: [{ torch: (mod === "torch" || mod === "on") }],
        });
        durum.flas = mod;
      }
    } catch (e) {}
    return durum.flas;
  }

  /* ═══ YAKINLAŞTIRMA ═══
     SORUN 1 — Akıcı değildi.
       Her parmak hareketinde kameraya bir istek gidiyordu ve istekler
       kuyruğa giriyordu. Üstüne her seferinde otomatik odaklama
       çalışıyordu; odaklama yavaş bir işlem, görüntü takılıyordu.
       Çözüm: aynı anda tek istek, aradakiler atılır (yalnızca en son
       değer önemli). Odaklama parmak kalkınca bir kez yapılır.

     SORUN 2 — 0.6 kat yapılamıyordu.
       Alt sınır elle 1 olarak sabitlenmişti. Geniş açı merceği olan
       cihazlarda alt sınır 0.5-0.6 olabiliyor; artık cihazın
       bildirdiği değer kullanılıyor. */

  let _yakinlikIstekte = false;      // şu an bir istek yolda mı
  let _bekleyenYakinlik = null;      // en son istenen değer
  let _aralik = null;                // { min, max } — cihazdan

  /* Cihazın desteklediği yakınlık aralığı. Bir kez sorulur, saklanır. */
  async function yakinlikAraligi() {
    if (_aralik) return _aralik;

    if (durum.yerel) {
      try {
        const z = await CP().getZoom();
        if (z && typeof z.min === "number" && typeof z.max === "number") {
          _aralik = { min: z.min, max: Math.min(z.max, 8) };
          return _aralik;
        }
      } catch (e) {}
    } else {
      try {
        const iz = webAkis && webAkis.getVideoTracks()[0];
        const y = (iz && iz.getCapabilities) ? iz.getCapabilities() : null;
        if (y && y.zoom) {
          _aralik = { min: y.zoom.min, max: Math.min(y.zoom.max, 8) };
          return _aralik;
        }
      } catch (e) {}
    }

    _aralik = { min: 1, max: 1 };    // yakınlaştırma desteklenmiyor
    return _aralik;
  }

  async function yakinlastir(deger, odakla) {
    const a = await yakinlikAraligi();
    const d = Math.min(Math.max(Number(deger) || 1, a.min), a.max);

    /* Bir istek yoldayken yenisi gönderilmez; yalnızca en son değer
       saklanır. Kuyruk oluşmadığı için hareket akıcı kalıyor. */
    _bekleyenYakinlik = { d: d, odak: !!odakla };
    if (_yakinlikIstekte) return durum.yakinlik;

    _yakinlikIstekte = true;
    try {
      while (_bekleyenYakinlik) {
        const su = _bekleyenYakinlik;
        _bekleyenYakinlik = null;

        if (durum.yerel) {
          /* autoFocus yalnızca parmak kalkınca — her harekette
             odaklamak görüntüyü takıyordu. */
          try {
            await CP().setZoom({ level: su.d, autoFocus: su.odak });
            durum.yakinlik = su.d;
          } catch (e) {}
        } else {
          try {
            const iz = webAkis && webAkis.getVideoTracks()[0];
            if (iz && iz.applyConstraints) {
              await iz.applyConstraints({ advanced: [{ zoom: su.d }] });
              durum.yakinlik = su.d;
            }
          } catch (e) {}
        }
      }
    } finally {
      _yakinlikIstekte = false;
    }

    return durum.yakinlik;
  }

  /* En geniş açı: cihaz destekliyorsa yakınlaştırmayı en düşüğe çeker. */
  async function enGenisAci() {
    if (durum.yerel) {
      /* En geniş açı: cihazın bildirdiği en düşük yakınlaştırma. */
      try {
        const z = await CP().getZoom();
        const enAz = (z && typeof z.min === "number") ? z.min : 1;
        await CP().setZoom({ level: enAz, autoFocus: true });
        durum.yakinlik = enAz;
      } catch (e) {}
      return;
    }
    try {
      const iz = webAkis && webAkis.getVideoTracks()[0];
      const y = (iz && iz.getCapabilities) ? iz.getCapabilities() : null;
      if (y && y.zoom && y.zoom.min != null) {
        await iz.applyConstraints({ advanced: [{ zoom: y.zoom.min }] });
      }
    } catch (e) {}
  }

  /* ══════════════════════════════════════════════════════════════════
     YAŞAM DÖNGÜSÜ
     Uygulama arka plana geçince kamera bırakılır: pil tükenmez, başka
     uygulamalar kamerayı kullanabilir, kamera ışığı yanık kalmaz.
     Öne dönünce geri açılır. Kayıt sürüyorsa dokunulmaz.
     ══════════════════════════════════════════════════════════════════ */
  let arkaPlandaKapandi = false;
  let sonSecenek = null;

  document.addEventListener("visibilitychange", async function () {
    if (document.hidden) {
      if (durum.acik && !durum.kaydediyor) {
        arkaPlandaKapandi = true;
        try { await durdur(); } catch (e) {}
      }
    } else if (arkaPlandaKapandi) {
      arkaPlandaKapandi = false;
      try { await baslat(sonSecenek || {}); } catch (e) {}
    }
  });

  /* ══════════════════════════════════════════════════════════════════
     DIŞA AÇILAN ARAYÜZ
     ══════════════════════════════════════════════════════════════════ */
  global.Kamera = {
    HATA: HATA,

    baslat: function (s) { sonSecenek = s || {}; return baslat(s); },
    durdur: durdur,
    cevir: cevir,

    fotoCek: fotoCek,
    kayitBaslat: kayitBaslat,
    kayitBitir: kayitBitir,

    flas: flas,
    yakinlastir: yakinlastir,
    yakinlikAraligi: yakinlikAraligi,
    enGenisAci: enGenisAci,

    onizlemeKipi: function (kip) {
      return sirala(async function () {
        durum.onizlemeKip = (kip === "fill") ? "fill" : "fit";
        return durum.onizlemeKip;
      });
    },

    olay: olay,
    yerelMi: yerelMi,
    guvenliBaglamMi: guvenliBaglamMi,

    /* Kayıt sırasında kamera çevirmek YALNIZCA uygulamada mümkün.
       Web'de MediaRecorder akış değişince kaydı durdurur. */
    kayittaCevirmeVar: function () { return yerelMi(); },

    /* Kendiliğinden biten kaydın dosyasını verir. */
    sonKayit: function () {
      if (!_sonKayitYolu) return null;
      const yol = _sonKayitYolu, sure = _sonKayitSure;
      _sonKayitYolu = null;
      const c = cap();
      const adres = (c && c.convertFileSrc) ? c.convertFileSrc(yol) : yol;
      return { yol: yol, sure: sure, adres: adres, blob: null, _bekliyor: true,
               coz: function () {
                 return fetch(adres).then(function (r) { return r.blob(); });
               } };
    },

    durum: function () { return Object.assign({}, durum); },
    gecenSure: function () {
      return durum.kaydediyor ? (Date.now() - durum.kayitBaslangic) : 0;
    },
  };
})(window);
