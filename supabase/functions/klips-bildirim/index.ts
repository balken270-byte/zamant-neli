// ============================================================================
// KLİPSY — BİLDİRİM GÖNDERİCİ (2/3)
// ============================================================================
// Supabase Edge Function. notifications tablosuna satır düştüğünde
// tetikleyici tarafından çağrılır ve bildirimi Firebase üzerinden
// kullanıcının telefonuna iletir.
//
// KURULUM
//   1. Bu dosyayı şuraya koy:  supabase/functions/klipsy-push/index.ts
//   2. Firebase servis hesabı anahtarını gizli değer olarak ekle:
//        npx supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat servis-hesabi.json)"
//   3. Yayınla:
//        npx supabase functions deploy klipsy-push --no-verify-jwt
//
// NOT: Eski FCM API'leri kaldırıldı; burada v1 protokolü kullanılıyor.
//      v1, OAuth 2.0 ile kimlik doğrular — servis hesabı anahtarı bu yüzden gerekli.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Firebase erişim jetonu üret (OAuth 2.0, servis hesabıyla) ──────────────
let _jeton: { deger: string; bitis: number } | null = null;

async function firebaseJetonu(hesap: any): Promise<string> {
  const simdi = Math.floor(Date.now() / 1000);
  if (_jeton && _jeton.bitis > simdi + 60) return _jeton.deger;

  const baslik = { alg: "RS256", typ: "JWT" };
  const govde = {
    iss: hesap.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: simdi,
    exp: simdi + 3600,
  };

  const b64 = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const imzalanacak = `${b64(baslik)}.${b64(govde)}`;

  // PEM anahtarı içe aktar
  const pem = hesap.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const ham = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));

  const anahtar = await crypto.subtle.importKey(
    "pkcs8",
    ham,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const imza = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    anahtar,
    new TextEncoder().encode(imzalanacak),
  );

  const imzaB64 = btoa(String.fromCharCode(...new Uint8Array(imza)))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const jwt = `${imzalanacak}.${imzaB64}`;

  const cevap = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const veri = await cevap.json();
  if (!veri.access_token) throw new Error("Firebase jetonu alınamadı: " + JSON.stringify(veri));

  _jeton = { deger: veri.access_token, bitis: simdi + 3500 };
  return _jeton.deger;
}

// ── Bildirim metnini hazırla ───────────────────────────────────────────────
function metinKur(kayit: any, kimden: string) {
  /* WHATSAPP DÜZENİ
       başlık → kişinin ADI SOYADI
       gövde  → ne yaptığı
     Önceden başlıkta hep "Klipsy" yazıyordu; kimin ne yaptığı
     tek satıra sıkışıyordu. */
  const tur = kayit.kind || "";
  const ad = kimden || "Biri";
  const onizleme = (kayit.preview || "").toString().trim();

  if (tur === "like")         return { baslik: ad, govde: "anını beğendi" };
  if (tur === "follow")       return { baslik: ad, govde: "seni takip etmeye başladı" };
  if (tur === "comment_like") return { baslik: ad, govde: "yorumunu beğendi" };

  if (tur === "comment") {
    return { baslik: ad, govde: onizleme || "anına yorum yaptı" };
  }
  if (tur === "reply") {
    return { baslik: ad, govde: onizleme || "yorumuna yanıt verdi" };
  }
  if (tur === "message") {
    return { baslik: ad, govde: onizleme || "Yeni mesaj" };
  }
  return { baslik: ad, govde: "Yeni bildirim" };
}

// ── Ana akış ───────────────────────────────────────────────────────────────
Deno.serve(async (istek) => {
  try {
    const { record } = await istek.json();
    if (!record || !record.user_id) {
      return new Response(JSON.stringify({ atlandi: "kayıt yok" }), { status: 200 });
    }

    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Bildirimi alacak kişinin cihaz anahtarları
    const { data: cihazlar } = await sb
      .from("device_tokens")
      .select("token")
      .eq("user_id", record.user_id);

    if (!cihazlar || cihazlar.length === 0) {
      return new Response(JSON.stringify({ atlandi: "cihaz yok" }), { status: 200 });
    }

    // Bildirimi yapan kişinin adı
    let kimden = "";
    let kimdenKullanici = "";
    let avatar = "";
    let anGorseli = "";
    if (record.actor_id) {
      const { data: p } = await sb
        .from("profiles")
        .select("username, display_name, avatar_url")
        .eq("id", record.actor_id)
        .single();
      kimden = (p?.display_name || p?.username || "").toString();
      kimdenKullanici = (p?.username || "").toString();
      avatar = (p?.avatar_url || "").toString();
    }

    /* Anın kapağı — bildirimde büyük görsel olarak gösterilir.
       Hangi paylaşımın kastedildiği yazıyı okumadan anlaşılır. */
    if (record.moment_id) {
      const { data: m } = await sb
        .from("moments")
        .select("thumb_path, poster_path, media_path, media_kind")
        .eq("id", record.moment_id)
        .single();
      if (m) {
        const yol = m.thumb_path || m.poster_path ||
                    (m.media_kind !== "video" ? m.media_path : null);
        if (yol) {
          anGorseli = sb.storage.from("moments").getPublicUrl(yol).data.publicUrl;
        }
      }
    }

    const { baslik, govde } = metinKur(record, kimden);

    const hesap = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
    const jeton = await firebaseJetonu(hesap);
    const url = `https://fcm.googleapis.com/v1/projects/${hesap.project_id}/messages:send`;

    const sonuclar: any[] = [];

    for (const c of cihazlar) {
      const cevap = await fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${jeton}`,
          "Content-Type": "application/json",
        },
        /* MESAJLAR: SADECE VERİ.
           Yanıt düğmesi ancak bildirimi biz kurarsak eklenebiliyor;
           hazır bildirim gönderilirse Android kendi gösterir ve
           servisimiz hiç çağrılmaz.
           Diğer türlerde hazır bildirim kullanılır — orada yanıt
           düğmesine gerek yok, güvenli yol tercih edilir. */
        /* TÜM TÜRLER SADECE VERİ OLARAK GİDER.
           Hazır bildirim gönderilirse Android onu kendisi çiziyor ve
           uygulamanın kendi tasarımı (yığınlama, profil fotoğrafı,
           anın kapağı) devreye girmiyordu.
           Artık bildirimi her durumda uygulama kuruyor. */
        body: JSON.stringify({
          message: {
            token: c.token,
            /* Uygulama AÇIKKEN gelen bildirim için gereken bilgiler.
               Android bu durumda sistem bildirimi göstermez, veriyi
               uygulamaya verir; şerit bunlarla çiziliyor. */
            data: {
              kind: String(record.kind || ""),
              moment_id: String(record.moment_id || ""),
              actor: kimdenKullanici,
              actor_name: kimden,
              /* Yanıtın doğrudan gönderileceği kimlik.
                 Bu olmadan yerel kod kullanıcı adından kimlik çözmek
                 zorunda kalıyor; fazladan sorgu ve hata kaynağı. */
              actor_id: String(record.actor_id || ""),
              conv_id: String(record.conv_id || ""),
              /* Yığın anahtarı — aynı gruptakiler tek kartta toplanır. */
              grup: (record.kind === "message")
                      ? ("mesaj:" + String(record.actor_id || ""))
                      : "etkilesim",
              avatar: avatar,
              image: anGorseli,
              title: baslik,
              body: govde,
            },
            android: {
              /* Yüksek öncelik: cihaz uyku kipindeyken de teslim edilsin. */
              priority: "high",
            },
          },
        }),
      });

      const s = await cevap.json();

      /* Firebase'in cevabı AÇIKÇA bildirilir.
         Önceden yalnızca deneme sayısı dönüyordu; Firebase reddetse
         bile "gönderildi" görünüyordu ve sorun görünmez kalıyordu. */
      sonuclar.push({
        basarili: cevap.ok,
        durum: cevap.status,
        // hata varsa sebebini kısaca ver
        hata: cevap.ok ? null : (s?.error?.message || s?.error?.status || JSON.stringify(s).slice(0, 200)),
        anahtar_sonu: String(c.token).slice(-8),
      });

      console.log("FCM sonuç:", cevap.status, JSON.stringify(s).slice(0, 400));

      // Geçersiz anahtarları temizle (uygulama silinmiş olabilir)
      if (!cevap.ok && (s?.error?.status === "NOT_FOUND" ||
                        s?.error?.status === "UNREGISTERED")) {
        await sb.from("device_tokens").delete().eq("token", c.token);
      }
    }

    const basarili = sonuclar.filter((r) => r.basarili).length;

    return new Response(
      JSON.stringify({
        cihaz: cihazlar.length,
        basarili,
        basarisiz: sonuclar.length - basarili,
        ayrinti: sonuclar,
      }),
      { status: 200 },
    );
  } catch (e) {
    const mesaj = (e && (e as Error).message) ? (e as Error).message : String(e);
    console.error("bildirim hatası:", mesaj);
    return new Response(JSON.stringify({ hata: mesaj }), { status: 200 });
  }
});
