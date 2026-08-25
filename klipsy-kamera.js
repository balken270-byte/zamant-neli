/* ============================================================================
   KLİPSY — KAMERA KATMANI
   ============================================================================
   NEDEN AYRI DOSYA
     Kamera bu uygulamanın bel kemiği. Tarayıcı yolu (getUserMedia +
     MediaRecorder) telefonda akıcı değil: görüntü tarayıcıdan geçiyor,
     kayıt yazılımla yapılıyor ve kare düşüyor.

     Bu katman iki yolu ayırır:
       UYGULAMADA  → Android'in kendi kamerası (CameraX). Önizleme ve kayıt
                     donanımda yapılır, tarayıcı hiç karışmaz. TikTok'un
                     yaptığı da budur.
       WEB'DE      → getUserMedia ile arka kamera. Denemek isteyen görsün;
                     ciddi çekim uygulamada yapılır.

   KULLANIM
     await Kamera.baslat({ yon:'arka' });   // önizlemeyi aç
     await Kamera.cevir();                  // ön/arka
     const foto  = await Kamera.fotoCek();  // data URL döner
     await Kamera.kayitBaslat();
     const video = await Kamera.kayitBitir(); // { blob, sure }
     await Kamera.durdur();

   Kamera.yerelMi() → uygulamada mı çalışıyor
   ============================================================================ */

(function (global) {
  "use strict";

  /* ── Ortam tespiti ─────────────────────────────────────────────────── */
  function yerelMi() {
    try {
      const c = global.Capacitor;
      if (!c || !c.isNativePlatform || !c.isNativePlatform()) return false;
      const P = c.Plugins || {};
      return !!P.CameraPreview;
    } catch (e) { return false; }
  }

  function eklenti() {
    const c = global.Capacitor;
    return (c && c.Plugins && c.Plugins.CameraPreview) || null;
  }

  /* ── Durum ─────────────────────────────────────────────────────────── */
  const durum = {
    acik: false,
    kaydediyor: false,
    yon: "arka",          // 'arka' | 'on'
    kayitBaslangic: 0,
  };

  let webAkis = null;     // web yolunda MediaStream
  let webKayit = null;    // web yolunda MediaRecorder
  let webParcalar = [];

  const yonNative = (y) => (y === "on" ? "front" : "rear");

  /* ══════════════════════════════════════════════════════════════════
     BAŞLAT
     ══════════════════════════════════════════════════════════════════ */
  async function baslat(secenek) {
    secenek = secenek || {};
    if (durum.acik) return;

    durum.yon = secenek.yon || "arka";

    if (yerelMi()) {
      /* Yerel önizleme, HTML'in ARKASINA yerleşir (toBack).
         Böylece düğmeler ve yazılar üstte kalır, görüntü donanımdan
         doğrudan ekrana çizilir — tarayıcı katmanı yok. */
      const CP = eklenti();
      await CP.start({
        position: yonNative(durum.yon),
        parent: secenek.kap || "camRoot",
        className: "camNativePreview",
        toBack: true,
        x: 0, y: 0,
        width: Math.round(global.innerWidth),
        height: Math.round(global.innerHeight),
        disableAudio: false,      // video kaydında ses gerekiyor
        enableZoom: true,
        storeToFile: true,
        enableHighResolution: true,
      });

      // gövdeye işaret: arka plan saydam olmalı, yoksa önizleme görünmez
      document.documentElement.classList.add("camNativeOn");
      durum.acik = true;
      return;
    }

    /* ── WEB YOLU ──
       Yalnızca arka kamera. Orana karışılmaz; kamera kendi geniş
       görüntüsünü versin (istenirse sensör kenarları kırpılıyor). */
    const kisit = {
      video: {
        facingMode: { ideal: "environment" },
        width: { ideal: 1920 },
        frameRate: { ideal: 30, min: 24 },
      },
      audio: secenek.ses !== false,
    };

    webAkis = await navigator.mediaDevices.getUserMedia(kisit);

    const v = document.getElementById(secenek.video || "camVideo");
    if (v) {
      v.srcObject = webAkis;
      v.muted = true;
      v.playsInline = true;
      try { await v.play(); } catch (e) {}
    }
    durum.acik = true;
  }

  /* ══════════════════════════════════════════════════════════════════
     DURDUR
     ══════════════════════════════════════════════════════════════════ */
  async function durdur() {
    if (!durum.acik) return;

    if (durum.kaydediyor) {
      try { await kayitBitir(); } catch (e) {}
    }

    if (yerelMi()) {
      try { await eklenti().stop(); } catch (e) {}
      document.documentElement.classList.remove("camNativeOn");
    } else {
      if (webAkis) {
        try { webAkis.getTracks().forEach((t) => t.stop()); } catch (e) {}
        webAkis = null;
      }
      const v = document.getElementById("camVideo");
      if (v) v.srcObject = null;
    }

    durum.acik = false;
  }

  /* ══════════════════════════════════════════════════════════════════
     KAMERA ÇEVİR
     ══════════════════════════════════════════════════════════════════ */
  async function cevir() {
    if (!durum.acik) return;
    durum.yon = durum.yon === "on" ? "arka" : "on";

    if (yerelMi()) {
      /* Yerel tarafta çevirme kaydı BÖLMEZ — CameraX akışı sürdürür.
         Tarayıcı yolunda bu mümkün değildi. */
      try { await eklenti().flip(); } catch (e) {}
      return;
    }

    /* Web'de yalnızca arka kamera destekleniyor; çevirme yok.
       (Ön kamera isteyen uygulamayı kullanır.) */
    durum.yon = "arka";
  }

  /* ══════════════════════════════════════════════════════════════════
     FOTOĞRAF
     ══════════════════════════════════════════════════════════════════ */
  async function fotoCek(kalite) {
    if (!durum.acik) return null;
    kalite = kalite || 88;

    if (yerelMi()) {
      const r = await eklenti().capture({ quality: kalite });
      const v = r && (r.value || r.base64 || r.data);
      if (!v) return null;
      return /^data:/.test(v) ? v : "data:image/jpeg;base64," + v;
    }

    /* Web: görüntüden kare al. Tek seferlik olduğu için maliyeti yok —
       sürekli çizim yapılmıyor. */
    const v = document.getElementById("camVideo");
    if (!v || !v.videoWidth) return null;

    const c = document.createElement("canvas");
    c.width = v.videoWidth;
    c.height = v.videoHeight;
    c.getContext("2d").drawImage(v, 0, 0);
    return c.toDataURL("image/jpeg", kalite / 100);
  }

  /* ══════════════════════════════════════════════════════════════════
     VİDEO KAYDI
     ══════════════════════════════════════════════════════════════════ */
  async function kayitBaslat() {
    if (!durum.acik || durum.kaydediyor) return;

    if (yerelMi()) {
      /* Kayıt donanımda yapılır: görüntü hiç JavaScript'ten geçmez.
         Donmanın asıl sebebi buydu. */
      await eklenti().startRecordVideo({ storeToFile: true });
      durum.kaydediyor = true;
      durum.kayitBaslangic = Date.now();
      return;
    }

    /* Web: doğrudan akıştan kayıt. Tuval KULLANILMAZ —
       her kareyi JavaScript ile kopyalamak kaydı dondurur. */
    if (!webAkis) return;

    const turler = [
      "video/mp4;codecs=h264,aac",
      "video/webm;codecs=vp9,opus",
      "video/webm;codecs=vp8,opus",
      "video/webm",
    ];
    let tur = "";
    for (const t of turler) {
      if (global.MediaRecorder && MediaRecorder.isTypeSupported(t)) { tur = t; break; }
    }

    webParcalar = [];
    try {
      webKayit = tur
        ? new MediaRecorder(webAkis, { mimeType: tur, videoBitsPerSecond: 3400000 })
        : new MediaRecorder(webAkis);
    } catch (e) {
      webKayit = new MediaRecorder(webAkis);
    }

    webKayit.ondataavailable = (e) => { if (e.data && e.data.size) webParcalar.push(e.data); };
    webKayit.start(250);
    durum.kaydediyor = true;
    durum.kayitBaslangic = Date.now();
  }

  async function kayitBitir() {
    if (!durum.kaydediyor) return null;
    const sure = Date.now() - durum.kayitBaslangic;

    if (yerelMi()) {
      const r = await eklenti().stopRecordVideo();
      durum.kaydediyor = false;
      const yol = r && (r.videoFilePath || r.value || r.path);
      if (!yol) return null;

      /* Dosya yolunu tarayıcının okuyabileceği adrese çevir,
         sonra yükleme için veri parçasına dönüştür. */
      let blob = null;
      try {
        const c = global.Capacitor;
        const adres = (c && c.convertFileSrc) ? c.convertFileSrc(yol) : yol;
        const cevap = await fetch(adres);
        blob = await cevap.blob();
      } catch (e) {}

      return { blob: blob, yol: yol, sure: sure };
    }

    // web
    return await new Promise((coz) => {
      if (!webKayit) { durum.kaydediyor = false; coz(null); return; }
      webKayit.onstop = () => {
        const tur = webParcalar[0] ? webParcalar[0].type : "video/webm";
        const blob = new Blob(webParcalar, { type: tur });
        webParcalar = [];
        webKayit = null;
        durum.kaydediyor = false;
        coz({ blob: blob, yol: null, sure: sure });
      };
      try { webKayit.stop(); } catch (e) { durum.kaydediyor = false; coz(null); }
    });
  }

  /* ══════════════════════════════════════════════════════════════════
     EK AYARLAR
     ══════════════════════════════════════════════════════════════════ */
  async function flas(mod) {
    if (!yerelMi()) return;
    try { await eklenti().setFlashMode({ flashMode: mod || "off" }); } catch (e) {}
  }

  async function yakinlastir(deger) {
    if (!yerelMi()) return;
    try { await eklenti().setZoom({ zoom: deger }); } catch (e) {}
  }

  /* ── Dışa açılan arayüz ─────────────────────────────────────────── */
  global.Kamera = {
    baslat: baslat,
    durdur: durdur,
    cevir: cevir,
    fotoCek: fotoCek,
    kayitBaslat: kayitBaslat,
    kayitBitir: kayitBitir,
    flas: flas,
    yakinlastir: yakinlastir,
    yerelMi: yerelMi,
    durum: () => Object.assign({}, durum),
  };
})(window);
