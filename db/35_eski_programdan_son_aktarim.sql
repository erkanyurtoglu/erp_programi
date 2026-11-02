-- ============================================================================
-- 35_eski_programdan_son_aktarim.sql
--
-- ISTEK
-- db/02 gocu 19-20.10.2026'da yapildi; eski WPF programi (LiyaTeklifVeriTabani)
-- o gunden beri kullanilmaya devam ediyor. Gecis gunu, eski programda gocten
-- sonra yapilan isler yeni veritabanina tasinmali.
--
-- KURAL
-- Satis verisinde (musteri, teklif, kalem, toplam, sevk) ESKI VERITABANI
-- ESASTIR. Yeni programda gecise kadar acilan teklifler testtir ve silinir:
-- numaralari eski programdaki gercek tekliflerle cakisiyor (or. yeni 5624 bir
-- test, eski 5624 musteriye kabul edilmis gercek teklif).
--
-- Iki taraftaki teklifin AYNI teklif sayilmasi icin TeklifId ile birlikte
-- olusturma tarihi de tutmalidir. Eski kolon datetime, yeni datetime2: yeni
-- deger datetime'a cevrilerek karsilastirilir (aksi halde milisaniye
-- yuvarlamasi yuzunden binlerce teklif "farkli" gorunur).
--
-- NE YAPAR
--   1) Eski DB'de karsiligi olmayan teklifleri siler (yeni programda acilmis
--      testler). Kalemleri, toplamlari, sevk/durum/duzeltme gecmisi ON DELETE
--      CASCADE ile gider; teklife ozel "MANUEL-<id>" urun satirlari da silinir.
--   2) Personel: eski programda acilmis yeni personel ayni Id ile eklenir
--      (rolsuz; rol Yonetim > Personellerim'den verilir). Sifre db/02'deki gibi
--      duz metin yazilir, ilk giriste hash'e yukseltilir.
--   3) Musteriler: yeniler ayni Id ile eklenir, degisenler eskiye gore
--      guncellenir. Teklifin isaret ettigi ama eski programda silinmis musteri
--      icin "SİLİNMİŞ MÜŞTERİ (eski Id n)" satiri acilir (ilk gocteki gibi).
--   4) Urunler: yalnizca YENI urunler eklenir, db/26 + db/27 kurallariyla (TL
--      fiyati FiyatTL, USD/EUR fiyatlari, maliyet satis fiyatindan kucukse).
--      Mevcut urunlere dokunulmaz; yeni programda yapilan fiyat/arsiv
--      duzenlemeleri korunur. Kalemin isaret ettigi silinmis urun icin arsivli
--      "SILINMIS-<id>" satiri acilir.
--   5) Teklifler: yeniler ayni TeklifId ile eklenir (TeklifNo = TeklifId,
--      db/10 gibi). Mevcutlarin baslik alanlari eskiden farkliysa guncellenir
--      (durum, kabul/teslim tarihi...). Yalnizca yeni programa ait alanlar
--      (RedSebebi, revizyon, TeklifNo, GecerlilikGunu...) korunur.
--   6) Kalemler: kalemi eskiden farkli olan tekliflerde silinip eskiden yeniden
--      yazilir (db/02 gibi ParaBirimi TL, Kur 1).
--   7) Toplamlar ve sevk bilgileri eskiye gore eklenir/guncellenir. Sevkte
--      yeni programa ait alanlar (Irsaliye No, Fatura No/Tarihi) korunur.
--   8) Bu betigin dokundugu Kabul Edildi / Tamamlandı teklifler db/33
--      kuralina gore "Faturalandı" isaretlenir.
--
-- Eski veritabanina YALNIZCA OKUMA yapilir.
--
-- KULLANIM (gecis gunu, eski program kapatildiktan sonra)
--   0) LiyaErpVeriTabani'nin yedegini alin.
--   1) Oldugu gibi calistirin: yalnizca ONIZLEME gelir, veri degismez.
--   2) Onizlemedeki "Silinecek teklif" sayisini @OnaylananSilinecekTeklif'e
--      yazin, @Uygula = 1 yapip yeniden calistirin.
--   Sayi tutmazsa betik hicbir sey yapmadan durur: gecisten sonra yanlislikla
--   calistirilirsa yeni programda acilmis GERCEK teklifler silinmez.
--
-- Defalarca calistirilabilir; gecisten once denemek icin de kullanilabilir.
-- Onkosul: db/01-34.
-- ============================================================================
USE LiyaErpVeriTabani;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Uygula BIT = 0;                        -- 1 = aktar, 0 = yalnizca onizleme
DECLARE @OnaylananSilinecekTeklif INT = NULL;   -- onizlemedeki "Silinecek teklif" sayisi

IF DB_ID(N'LiyaTeklifVeriTabani') IS NULL
BEGIN
    RAISERROR(N'LiyaTeklifVeriTabani bulunamadı; hiçbir şey yapılmadı.', 16, 1);
    RETURN;
END

IF OBJECT_ID('tempdb..#silinecek') IS NOT NULL DROP TABLE #silinecek;
IF OBJECT_ID('tempdb..#eslesen') IS NOT NULL DROP TABLE #eslesen;
IF OBJECT_ID('tempdb..#eklenecekTeklif') IS NOT NULL DROP TABLE #eklenecekTeklif;
IF OBJECT_ID('tempdb..#baslikFarkli') IS NOT NULL DROP TABLE #baslikFarkli;
IF OBJECT_ID('tempdb..#kalemFarkli') IS NOT NULL DROP TABLE #kalemFarkli;
IF OBJECT_ID('tempdb..#kalemYaz') IS NOT NULL DROP TABLE #kalemYaz;
IF OBJECT_ID('tempdb..#eskiToplam') IS NOT NULL DROP TABLE #eskiToplam;
IF OBJECT_ID('tempdb..#toplamFarkli') IS NOT NULL DROP TABLE #toplamFarkli;
IF OBJECT_ID('tempdb..#eskiSevk') IS NOT NULL DROP TABLE #eskiSevk;
IF OBJECT_ID('tempdb..#sevkFarkli') IS NOT NULL DROP TABLE #sevkFarkli;
IF OBJECT_ID('tempdb..#eklenecekPersonel') IS NOT NULL DROP TABLE #eklenecekPersonel;
IF OBJECT_ID('tempdb..#eklenecekMusteri') IS NOT NULL DROP TABLE #eklenecekMusteri;
IF OBJECT_ID('tempdb..#guncellenecekMusteri') IS NOT NULL DROP TABLE #guncellenecekMusteri;
IF OBJECT_ID('tempdb..#musteriYerTutucu') IS NOT NULL DROP TABLE #musteriYerTutucu;
IF OBJECT_ID('tempdb..#eklenecekUrun') IS NOT NULL DROP TABLE #eklenecekUrun;
IF OBJECT_ID('tempdb..#urunYerTutucu') IS NOT NULL DROP TABLE #urunYerTutucu;
IF OBJECT_ID('tempdb..#fatura') IS NOT NULL DROP TABLE #fatura;

-- ---------------------------------------------------------------------------
-- A) Yapilacaklar hesaplanir (iki modda da; veri degismez)
-- ---------------------------------------------------------------------------

-- Teklifler
SELECT n.TeklifId, n.TeklifNo, n.RevizyonNo, n.OlusturmaTarihi, n.KullaniciId, n.MusteriId, n.Durum
INTO #silinecek
FROM dbo.teklifler n
WHERE NOT EXISTS (SELECT 1 FROM LiyaTeklifVeriTabani.dbo.teklifler o
                  WHERE o.TeklifId = n.TeklifId
                    AND o.OlusturmaTarihi = CAST(n.OlusturmaTarihi AS DATETIME));

SELECT o.TeklifId
INTO #eslesen
FROM LiyaTeklifVeriTabani.dbo.teklifler o
JOIN dbo.teklifler n ON n.TeklifId = o.TeklifId
                    AND o.OlusturmaTarihi = CAST(n.OlusturmaTarihi AS DATETIME);

SELECT o.TeklifId
INTO #eklenecekTeklif
FROM LiyaTeklifVeriTabani.dbo.teklifler o
WHERE NOT EXISTS (SELECT 1 FROM #eslesen e WHERE e.TeklifId = o.TeklifId);

SELECT o.TeklifId
INTO #baslikFarkli
FROM LiyaTeklifVeriTabani.dbo.teklifler o
JOIN #eslesen e ON e.TeklifId = o.TeklifId
JOIN dbo.teklifler n ON n.TeklifId = o.TeklifId
WHERE EXISTS (
    SELECT o.MusteriId, o.PersonelId, o.GenelIndirimOrani, o.KdvOrani, o.Durum, o.MusteriNotu,
           o.ParaBirimi, o.Dil, o.SatisSozlesmesiMetni, o.IlgiliKisi, o.IlgiliKisiTelefonu,
           o.IlgiliKisiEposta, o.TeslimatSekli, o.TeslimatYeri, o.TeslimatTarihi, o.TeslimTarihi,
           o.KabulTarihi, o.UretimPdfTarihi
    EXCEPT
    SELECT n.MusteriId, n.KullaniciId, n.GenelIndirimOrani, n.KdvOrani, n.Durum, n.MusteriNotu,
           n.ParaBirimi, n.Dil, n.SatisSozlesmesiMetni, n.IlgiliKisi, n.IlgiliKisiTelefonu,
           n.IlgiliKisiEposta, n.TeslimatSekli, n.TeslimatYeri,
           CAST(n.TeslimatTarihi AS DATETIME), CAST(n.TeslimTarihi AS DATETIME),
           CAST(n.KabulTarihi AS DATETIME), CAST(n.UretimPdfTarihi AS DATETIME));

-- Kalemler: icerik iki yonde karsilastirilir, ayrica adet (ayni satir iki kez
-- girilmis olabilir). TeklifKalemId karsilastirilmaz.
SELECT x.TeklifId
INTO #kalemFarkli
FROM (
    SELECT o.TeklifId, o.UrunId, o.Adet, o.BirimFiyat, o.IndirimliBirimFiyat, o.ToplamTutar,
           o.MaliyetFiyati, o.UrunAciklamasi, o.UrunAciklamasiTr, o.UrunAciklamasiEn,
           o.FiyatTL, o.FiyatUSD, o.FiyatEUR, ISNULL(o.Tamamlandi, 0) AS Tamamlandi,
           LEFT(o.UretimNotu, 1000) AS UretimNotu
    FROM LiyaTeklifVeriTabani.dbo.teklif_urunleri o
    JOIN #eslesen e ON e.TeklifId = o.TeklifId
    EXCEPT
    SELECT k.TeklifId, k.UrunId, k.Adet, k.BirimFiyat, k.IndirimliBirimFiyat, k.ToplamTutar,
           k.MaliyetFiyati, k.UrunAciklamasi, k.UrunAciklamasiTr, k.UrunAciklamasiEn,
           k.EskiFiyatTL, k.EskiFiyatUSD, k.EskiFiyatEUR, k.Tamamlandi, k.UretimNotu
    FROM dbo.teklif_kalemleri k
    JOIN #eslesen e ON e.TeklifId = k.TeklifId
) x
UNION
SELECT y.TeklifId
FROM (
    SELECT k.TeklifId, k.UrunId, k.Adet, k.BirimFiyat, k.IndirimliBirimFiyat, k.ToplamTutar,
           k.MaliyetFiyati, k.UrunAciklamasi, k.UrunAciklamasiTr, k.UrunAciklamasiEn,
           k.EskiFiyatTL, k.EskiFiyatUSD, k.EskiFiyatEUR, k.Tamamlandi, k.UretimNotu
    FROM dbo.teklif_kalemleri k
    JOIN #eslesen e ON e.TeklifId = k.TeklifId
    EXCEPT
    SELECT o.TeklifId, o.UrunId, o.Adet, o.BirimFiyat, o.IndirimliBirimFiyat, o.ToplamTutar,
           o.MaliyetFiyati, o.UrunAciklamasi, o.UrunAciklamasiTr, o.UrunAciklamasiEn,
           o.FiyatTL, o.FiyatUSD, o.FiyatEUR, ISNULL(o.Tamamlandi, 0),
           LEFT(o.UretimNotu, 1000)
    FROM LiyaTeklifVeriTabani.dbo.teklif_urunleri o
    JOIN #eslesen e ON e.TeklifId = o.TeklifId
) y
UNION
SELECT e.TeklifId
FROM #eslesen e
WHERE (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.teklif_urunleri o WHERE o.TeklifId = e.TeklifId)
   <> (SELECT COUNT(*) FROM dbo.teklif_kalemleri k WHERE k.TeklifId = e.TeklifId);

SELECT TeklifId INTO #kalemYaz FROM #eklenecekTeklif
UNION
SELECT TeklifId FROM #kalemFarkli;

-- Toplamlar: teklif basina en son satir
SELECT x.TeklifId, x.IndirimliToplam, x.KdvTutari, x.GenelToplam, x.PaketlemeUcreti, x.TasimaUcreti
INTO #eskiToplam
FROM (
    SELECT tt.*, ROW_NUMBER() OVER (PARTITION BY tt.TeklifId ORDER BY tt.ToplamId DESC) AS SiraNo
    FROM LiyaTeklifVeriTabani.dbo.teklif_toplamlari tt
    WHERE EXISTS (SELECT 1 FROM LiyaTeklifVeriTabani.dbo.teklifler t WHERE t.TeklifId = tt.TeklifId)
) x
WHERE x.SiraNo = 1;

SELECT d.TeklifId
INTO #toplamFarkli
FROM (
    SELECT TeklifId, IndirimliToplam, KdvTutari, GenelToplam, PaketlemeUcreti, TasimaUcreti
    FROM #eskiToplam
    EXCEPT
    SELECT tt.TeklifId, tt.IndirimliToplam, tt.KdvTutari, tt.GenelToplam, tt.PaketlemeUcreti, tt.TasimaUcreti
    FROM dbo.teklif_toplamlari tt
    WHERE NOT EXISTS (SELECT 1 FROM #silinecek s WHERE s.TeklifId = tt.TeklifId)
) d;

-- Sevk: db/02 gibi teklif basina en son (en yuksek Id'li) kayit
SELECT x.TeklifNoID AS TeklifId, x.FaturaBasligi, LEFT(x.FaturaAdresi, 500) AS FaturaAdresi,
       x.FaturaVergiDairesi, LEFT(x.FaturaVergiNo, 50) AS FaturaVergiNo, x.FaturaYetkili,
       x.FaturaTelefon, x.FaturaFax, x.FaturaEposta, x.IrsaliyeBasligi,
       LEFT(x.IrsaliyeAdresi, 500) AS IrsaliyeAdresi, x.IrsaliyeVergiDairesi,
       LEFT(x.IrsaliyeVergiNo, 50) AS IrsaliyeVergiNo, x.IrsaliyeYetkili, x.IrsaliyeTelefon,
       x.IrsaliyeEposta, x.SiparisKdv, x.FaturaSekli, x.Garanti, x.Teslimat, x.Odeme, x.Nakliye,
       x.Kalibrasyon, x.Egitim, x.ReferansNumarasi, x.EkFaturaNotu, x.Aciklamalar, x.SiparisTarihi
INTO #eskiSevk
FROM (
    SELECT sb.*, ROW_NUMBER() OVER (PARTITION BY sb.TeklifNoID ORDER BY sb.SevkBilgileriId DESC) AS SiraNo
    FROM LiyaTeklifVeriTabani.dbo.SevkBilgileri sb
    WHERE EXISTS (SELECT 1 FROM LiyaTeklifVeriTabani.dbo.teklifler t WHERE t.TeklifId = sb.TeklifNoID)
) x
WHERE x.SiraNo = 1;

SELECT d.TeklifId
INTO #sevkFarkli
FROM (
    SELECT * FROM #eskiSevk
    EXCEPT
    SELECT sb.TeklifId, sb.FaturaBasligi, sb.FaturaAdresi, sb.FaturaVergiDairesi, sb.FaturaVergiNo,
           sb.FaturaYetkili, sb.FaturaTelefon, sb.FaturaFax, sb.FaturaEposta, sb.IrsaliyeBasligi,
           sb.IrsaliyeAdresi, sb.IrsaliyeVergiDairesi, sb.IrsaliyeVergiNo, sb.IrsaliyeYetkili,
           sb.IrsaliyeTelefon, sb.IrsaliyeEposta, sb.SiparisKdv, sb.FaturaSekli, sb.Garanti,
           sb.Teslimat, sb.Odeme, sb.Nakliye, sb.Kalibrasyon, sb.Egitim, sb.ReferansNumarasi,
           sb.EkFaturaNotu, sb.Aciklamalar, sb.SiparisTarihi
    FROM dbo.sevk_bilgileri sb
    WHERE NOT EXISTS (SELECT 1 FROM #silinecek s WHERE s.TeklifId = sb.TeklifId)
) d;

-- Personel: Id'si ve kullanici adi bosta olanlar eklenebilir
SELECT p.PersonelId, p.AdSoyad, p.KullaniciAdi,
       CASE WHEN EXISTS (SELECT 1 FROM dbo.kullanicilar k WHERE k.KullaniciAdi = p.KullaniciAdi)
            THEN 0 ELSE 1 END AS Eklenebilir
INTO #eklenecekPersonel
FROM LiyaTeklifVeriTabani.dbo.personeller p
WHERE NOT EXISTS (SELECT 1 FROM dbo.kullanicilar k WHERE k.KullaniciId = p.PersonelId);

-- Musteriler
SELECT o.MusteriId
INTO #eklenecekMusteri
FROM LiyaTeklifVeriTabani.dbo.musteriler o
WHERE NOT EXISTS (SELECT 1 FROM dbo.musteriler n WHERE n.MusteriId = o.MusteriId);

SELECT o.MusteriId
INTO #guncellenecekMusteri
FROM LiyaTeklifVeriTabani.dbo.musteriler o
JOIN dbo.musteriler n ON n.MusteriId = o.MusteriId
WHERE EXISTS (
    SELECT LEFT(o.FirmaAdi, 250), o.FirmaAdresi, o.FirmaTelefonu, LEFT(o.FirmaEposta, 100),
           o.VergiDairesi, o.VergiNumarasi, LEFT(o.IlgiliKisi, 150), o.IlgiliKisiTelefonu
    EXCEPT
    SELECT n.FirmaAdi, n.FirmaAdresi, n.FirmaTelefonu, n.FirmaEposta,
           n.VergiDairesi, n.VergiNumarasi, n.IlgiliKisi, n.IlgiliKisiTelefonu);

SELECT DISTINCT o.MusteriId
INTO #musteriYerTutucu
FROM LiyaTeklifVeriTabani.dbo.teklifler o
WHERE (o.TeklifId IN (SELECT TeklifId FROM #eklenecekTeklif)
       OR o.TeklifId IN (SELECT TeklifId FROM #baslikFarkli))
  AND NOT EXISTS (SELECT 1 FROM LiyaTeklifVeriTabani.dbo.musteriler m WHERE m.MusteriId = o.MusteriId)
  AND NOT EXISTS (SELECT 1 FROM dbo.musteriler m WHERE m.MusteriId = o.MusteriId);

-- Urunler
SELECT o.UrunId
INTO #eklenecekUrun
FROM LiyaTeklifVeriTabani.dbo.urunler o
WHERE NOT EXISTS (SELECT 1 FROM dbo.urunler n WHERE n.UrunId = o.UrunId);

SELECT k.UrunId, MAX(k.UrunAciklamasi) AS UrunAciklamasi, MAX(k.BirimFiyat) AS BirimFiyat
INTO #urunYerTutucu
FROM LiyaTeklifVeriTabani.dbo.teklif_urunleri k
JOIN #kalemYaz y ON y.TeklifId = k.TeklifId
WHERE NOT EXISTS (SELECT 1 FROM LiyaTeklifVeriTabani.dbo.urunler u WHERE u.UrunId = k.UrunId)
  AND NOT EXISTS (SELECT 1 FROM dbo.urunler u WHERE u.UrunId = k.UrunId)
GROUP BY k.UrunId;

-- Fatura isaretleme (db/33 kurali), aktarim SONRASI degerlerle: durum eski
-- tekliften, AÇIKLAMALAR eski sevkten, Fatura No yeni taraftan. db/33'ten tek
-- fark: daha once BİLİNMİYOR yazilmis bir kaydin AÇIKLAMALAR'ina eski
-- programda "kesildi" yazildiysa ESKİ KAYIT'a cevrilir.
SELECT o.TeklifId, o.Durum,
       CASE WHEN UPPER(es.Aciklamalar) LIKE N'%FA%KES_LD_%'
              OR UPPER(es.Aciklamalar) LIKE N'%FA%ED_LD_%'
              OR UPPER(es.Aciklamalar) + N' ' LIKE N'%FATURALAND_[^R]%'
            THEN N'ESKİ KAYIT' ELSE N'BİLİNMİYOR' END AS YeniFaturaNo,
       NULLIF(LTRIM(RTRIM(sb.FaturaNo)), N'') AS MevcutFaturaNo
INTO #fatura
FROM LiyaTeklifVeriTabani.dbo.teklifler o
LEFT JOIN #eskiSevk es ON es.TeklifId = o.TeklifId
LEFT JOIN dbo.sevk_bilgileri sb ON sb.TeklifId = o.TeklifId
                               AND NOT EXISTS (SELECT 1 FROM #silinecek s WHERE s.TeklifId = sb.TeklifId)
WHERE o.Durum IN (N'Kabul Edildi', N'Tamamlandı')
  AND (o.TeklifId IN (SELECT TeklifId FROM #eklenecekTeklif)
       OR o.TeklifId IN (SELECT TeklifId FROM #baslikFarkli)
       OR o.TeklifId IN (SELECT TeklifId FROM #sevkFarkli));

DELETE FROM #fatura WHERE MevcutFaturaNo IS NOT NULL AND MevcutFaturaNo <> N'BİLİNMİYOR';
DELETE FROM #fatura WHERE Durum = N'Kabul Edildi' AND YeniFaturaNo = N'BİLİNMİYOR';
DELETE FROM #fatura WHERE YeniFaturaNo = ISNULL(MevcutFaturaNo, N'');

-- ---------------------------------------------------------------------------
-- B) ONIZLEME
-- ---------------------------------------------------------------------------
DECLARE @SilinecekSayi INT = (SELECT COUNT(*) FROM #silinecek);

SELECT Islem, Adet FROM (VALUES
    ( 1, N'Silinecek teklif (yeni programda açılmış / eski programda yok)', @SilinecekSayi),
    ( 2, N'Eklenecek teklif', (SELECT COUNT(*) FROM #eklenecekTeklif)),
    ( 3, N'Başlığı eskiye göre güncellenecek teklif', (SELECT COUNT(*) FROM #baslikFarkli)),
    ( 4, N'Kalemleri yeniden yazılacak teklif (yeni hariç)', (SELECT COUNT(*) FROM #kalemFarkli)),
    ( 5, N'Yazılacak kalem', (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.teklif_urunleri k
                                WHERE k.TeklifId IN (SELECT TeklifId FROM #kalemYaz))),
    ( 6, N'Eklenecek / güncellenecek toplam', (SELECT COUNT(*) FROM #toplamFarkli)),
    ( 7, N'Eklenecek / güncellenecek sevk bilgisi', (SELECT COUNT(*) FROM #sevkFarkli)),
    ( 8, N'Eklenecek müşteri', (SELECT COUNT(*) FROM #eklenecekMusteri)),
    ( 9, N'Eskiye göre güncellenecek müşteri', (SELECT COUNT(*) FROM #guncellenecekMusteri)),
    (10, N'SİLİNMİŞ MÜŞTERİ yer tutucusu', (SELECT COUNT(*) FROM #musteriYerTutucu)),
    (11, N'Eklenecek ürün', (SELECT COUNT(*) FROM #eklenecekUrun)),
    (12, N'SILINMIS ürün yer tutucusu', (SELECT COUNT(*) FROM #urunYerTutucu)),
    (13, N'Eklenecek personel', (SELECT COUNT(*) FROM #eklenecekPersonel WHERE Eklenebilir = 1)),
    (14, N'Faturalandı işaretlenecek', (SELECT COUNT(*) FROM #fatura)),
    (15, N'SORUN: kullanıcı adı çakışan personel (0 olmalı)', (SELECT COUNT(*) FROM #eklenecekPersonel WHERE Eklenebilir = 0))
) v(Sira, Islem, Adet)
ORDER BY Sira;

SELECT s.TeklifId, s.TeklifNo, s.RevizyonNo, s.OlusturmaTarihi, k.AdSoyad AS Kullanici,
       m.FirmaAdi, s.Durum,
       CASE WHEN EXISTS (SELECT 1 FROM LiyaTeklifVeriTabani.dbo.teklifler o WHERE o.TeklifId = s.TeklifId)
            THEN N'Eski programda aynı numarada başka teklif var' ELSE N'' END AS Not_
FROM #silinecek s
LEFT JOIN dbo.kullanicilar k ON k.KullaniciId = s.KullaniciId
LEFT JOIN dbo.musteriler m ON m.MusteriId = s.MusteriId
ORDER BY s.TeklifId;

SELECT o.TeklifId, n.Durum AS YeniDurum, o.Durum AS EskiDurum, o.KabulTarihi, o.TeslimTarihi, m.FirmaAdi
FROM #baslikFarkli b
JOIN LiyaTeklifVeriTabani.dbo.teklifler o ON o.TeklifId = b.TeklifId
JOIN dbo.teklifler n ON n.TeklifId = b.TeklifId
LEFT JOIN LiyaTeklifVeriTabani.dbo.musteriler m ON m.MusteriId = o.MusteriId
ORDER BY o.TeklifId;

SELECT p.PersonelId, p.AdSoyad, p.KullaniciAdi,
       CASE WHEN p.Eklenebilir = 1 THEN N'Eklenecek (rolsüz)' ELSE N'Kullanıcı adı yeni DB''de var; elle ekleyin' END AS Durum
FROM #eklenecekPersonel p;

-- Yeni semada daha kisa olan alanlar kirpilir
SELECT Alan, Adet FROM (
    SELECT N'musteriler.FirmaAdi > 250' AS Alan, COUNT(*) AS Adet FROM LiyaTeklifVeriTabani.dbo.musteriler o
    WHERE (o.MusteriId IN (SELECT MusteriId FROM #eklenecekMusteri) OR o.MusteriId IN (SELECT MusteriId FROM #guncellenecekMusteri)) AND LEN(o.FirmaAdi) > 250
    UNION ALL
    SELECT N'musteriler.FirmaEposta > 100', COUNT(*) FROM LiyaTeklifVeriTabani.dbo.musteriler o
    WHERE (o.MusteriId IN (SELECT MusteriId FROM #eklenecekMusteri) OR o.MusteriId IN (SELECT MusteriId FROM #guncellenecekMusteri)) AND LEN(o.FirmaEposta) > 100
    UNION ALL
    SELECT N'musteriler.IlgiliKisi > 150', COUNT(*) FROM LiyaTeklifVeriTabani.dbo.musteriler o
    WHERE (o.MusteriId IN (SELECT MusteriId FROM #eklenecekMusteri) OR o.MusteriId IN (SELECT MusteriId FROM #guncellenecekMusteri)) AND LEN(o.IlgiliKisi) > 150
    UNION ALL
    SELECT N'teklif_kalemleri.UretimNotu > 1000', COUNT(*) FROM LiyaTeklifVeriTabani.dbo.teklif_urunleri k
    WHERE k.TeklifId IN (SELECT TeklifId FROM #kalemYaz) AND LEN(k.UretimNotu) > 1000
    UNION ALL
    SELECT N'sevk_bilgileri adres > 500 / vergi no > 50', COUNT(*) FROM LiyaTeklifVeriTabani.dbo.SevkBilgileri sb
    WHERE sb.TeklifNoID IN (SELECT TeklifId FROM #sevkFarkli)
      AND (LEN(sb.FaturaAdresi) > 500 OR LEN(sb.IrsaliyeAdresi) > 500 OR LEN(sb.FaturaVergiNo) > 50 OR LEN(sb.IrsaliyeVergiNo) > 50)
) k
WHERE Adet > 0;

-- ---------------------------------------------------------------------------
-- C) UYGULAMA
-- ---------------------------------------------------------------------------
IF @Uygula = 0
BEGIN
    PRINT N'Önizleme: veri değişmedi. Uygulamak için @OnaylananSilinecekTeklif = '
          + CAST(@SilinecekSayi AS NVARCHAR(10)) + N' ve @Uygula = 1 yapın.';
    RETURN;
END

IF @SilinecekSayi > 0 AND ISNULL(@OnaylananSilinecekTeklif, -1) <> @SilinecekSayi
BEGIN
    RAISERROR(N'Silinecek teklif sayısı %d, onaylanan %d. Önizlemeyi kontrol edip @OnaylananSilinecekTeklif değerini düzeltin. Hiçbir şey yapılmadı.',
              16, 1, @SilinecekSayi, @OnaylananSilinecekTeklif);
    RETURN;
END

BEGIN TRANSACTION;

-- 1) Yeni programda acilmis teklifler
DELETE FROM dbo.teklifler WHERE TeklifId IN (SELECT TeklifId FROM #silinecek);

DELETE u
FROM dbo.urunler u
JOIN #silinecek s ON u.UrunKodu = CONCAT(N'MANUEL-', s.TeklifId)
WHERE NOT EXISTS (SELECT 1 FROM dbo.teklif_kalemleri k WHERE k.UrunId = u.UrunId)
  AND NOT EXISTS (SELECT 1 FROM dbo.satinalma_kalemleri k WHERE k.UrunId = u.UrunId)
  AND NOT EXISTS (SELECT 1 FROM dbo.cihazlar c WHERE c.UrunId = u.UrunId);

-- 2) Personel
SET IDENTITY_INSERT dbo.kullanicilar ON;
INSERT INTO dbo.kullanicilar
    (KullaniciId, AdSoyad, KullaniciAdi, SifreHash, Telefon, Pozisyon, AktifMi, EklenmeTarihi)
SELECT p.PersonelId, LEFT(p.AdSoyad, 100), p.KullaniciAdi, p.Sifre, p.Telefon, LEFT(p.Pozisyon, 50),
       p.AktifMi, p.EklenmeTarihi
FROM LiyaTeklifVeriTabani.dbo.personeller p
JOIN #eklenecekPersonel e ON e.PersonelId = p.PersonelId AND e.Eklenebilir = 1;
SET IDENTITY_INSERT dbo.kullanicilar OFF;

-- 3) Musteriler
SET IDENTITY_INSERT dbo.musteriler ON;
INSERT INTO dbo.musteriler
    (MusteriId, FirmaAdi, FirmaAdresi, FirmaTelefonu, FirmaEposta, VergiDairesi, VergiNumarasi,
     IlgiliKisi, IlgiliKisiTelefonu, EklenmeTarihi)
SELECT o.MusteriId, LEFT(o.FirmaAdi, 250), o.FirmaAdresi, o.FirmaTelefonu, LEFT(o.FirmaEposta, 100),
       o.VergiDairesi, o.VergiNumarasi, LEFT(o.IlgiliKisi, 150), o.IlgiliKisiTelefonu, o.EklenmeTarihi
FROM LiyaTeklifVeriTabani.dbo.musteriler o
JOIN #eklenecekMusteri e ON e.MusteriId = o.MusteriId;

INSERT INTO dbo.musteriler (MusteriId, FirmaAdi)
SELECT y.MusteriId, CONCAT(N'SİLİNMİŞ MÜŞTERİ (eski Id ', y.MusteriId, N')')
FROM #musteriYerTutucu y;
SET IDENTITY_INSERT dbo.musteriler OFF;

UPDATE n
SET FirmaAdi           = LEFT(o.FirmaAdi, 250),
    FirmaAdresi        = o.FirmaAdresi,
    FirmaTelefonu      = o.FirmaTelefonu,
    FirmaEposta        = LEFT(o.FirmaEposta, 100),
    VergiDairesi       = o.VergiDairesi,
    VergiNumarasi      = o.VergiNumarasi,
    IlgiliKisi         = LEFT(o.IlgiliKisi, 150),
    IlgiliKisiTelefonu = o.IlgiliKisiTelefonu
FROM dbo.musteriler n
JOIN #guncellenecekMusteri g ON g.MusteriId = n.MusteriId
JOIN LiyaTeklifVeriTabani.dbo.musteriler o ON o.MusteriId = n.MusteriId;

-- 4) Urunler (db/26: TL fiyati FiyatTL, doviz fiyatlari > 0 ise;
--    db/27: maliyet satis fiyatina esit/buyukse bos)
SET IDENTITY_INSERT dbo.urunler ON;
INSERT INTO dbo.urunler
    (UrunId, UrunKodu, Kategori, UrunAciklamasi, UrunAciklamasiEn, BirimFiyat, ParaBirimi,
     GuncelMaliyetTL, EklenmeTarihi, FiyatUSD, FiyatEUR)
SELECT o.UrunId, o.UrunKodu, o.Kategori, o.UrunAciklamasi, o.UrunAciklamasiEn, f.TlFiyat, N'TL',
       CASE WHEN o.MaliyetFiyati > 0 AND NOT (f.TlFiyat > 0 AND o.MaliyetFiyati >= f.TlFiyat)
            THEN o.MaliyetFiyati END,
       o.EklenmeTarihi,
       CASE WHEN o.FiyatUSD > 0 THEN o.FiyatUSD END,
       CASE WHEN o.FiyatEUR > 0 THEN o.FiyatEUR END
FROM LiyaTeklifVeriTabani.dbo.urunler o
JOIN #eklenecekUrun e ON e.UrunId = o.UrunId
CROSS APPLY (SELECT CASE WHEN o.FiyatTL > 0 THEN o.FiyatTL ELSE o.BirimFiyat END AS TlFiyat) f;

INSERT INTO dbo.urunler (UrunId, UrunKodu, UrunAciklamasi, BirimFiyat, ParaBirimi, AktifMi)
SELECT y.UrunId, CONCAT(N'SILINMIS-', y.UrunId), y.UrunAciklamasi, y.BirimFiyat, N'TL', 0
FROM #urunYerTutucu y;
SET IDENTITY_INSERT dbo.urunler OFF;

-- 5) Teklifler
SET IDENTITY_INSERT dbo.teklifler ON;
INSERT INTO dbo.teklifler
    (TeklifId, MusteriId, KullaniciId, OlusturmaTarihi, GenelIndirimOrani, KdvOrani, Durum, MusteriNotu,
     ParaBirimi, Dil, SatisSozlesmesiMetni, IlgiliKisi, IlgiliKisiTelefonu, IlgiliKisiEposta,
     TeslimatSekli, TeslimatYeri, TeslimatTarihi, TeslimTarihi, KabulTarihi, UretimPdfTarihi, TeklifNo)
SELECT o.TeklifId, o.MusteriId, o.PersonelId, o.OlusturmaTarihi, o.GenelIndirimOrani, o.KdvOrani, o.Durum,
       o.MusteriNotu, o.ParaBirimi, o.Dil, o.SatisSozlesmesiMetni, o.IlgiliKisi, o.IlgiliKisiTelefonu,
       o.IlgiliKisiEposta, o.TeslimatSekli, o.TeslimatYeri, o.TeslimatTarihi, o.TeslimTarihi,
       o.KabulTarihi, o.UretimPdfTarihi, o.TeklifId
FROM LiyaTeklifVeriTabani.dbo.teklifler o
JOIN #eklenecekTeklif e ON e.TeklifId = o.TeklifId;
SET IDENTITY_INSERT dbo.teklifler OFF;

UPDATE n
SET MusteriId            = o.MusteriId,
    KullaniciId          = o.PersonelId,
    GenelIndirimOrani    = o.GenelIndirimOrani,
    KdvOrani             = o.KdvOrani,
    Durum                = o.Durum,
    MusteriNotu          = o.MusteriNotu,
    ParaBirimi           = o.ParaBirimi,
    Dil                  = o.Dil,
    SatisSozlesmesiMetni = o.SatisSozlesmesiMetni,
    IlgiliKisi           = o.IlgiliKisi,
    IlgiliKisiTelefonu   = o.IlgiliKisiTelefonu,
    IlgiliKisiEposta     = o.IlgiliKisiEposta,
    TeslimatSekli        = o.TeslimatSekli,
    TeslimatYeri         = o.TeslimatYeri,
    TeslimatTarihi       = o.TeslimatTarihi,
    TeslimTarihi         = o.TeslimTarihi,
    KabulTarihi          = o.KabulTarihi,
    UretimPdfTarihi      = o.UretimPdfTarihi
FROM dbo.teklifler n
JOIN #baslikFarkli b ON b.TeklifId = n.TeklifId
JOIN LiyaTeklifVeriTabani.dbo.teklifler o ON o.TeklifId = n.TeklifId;

-- 6) Kalemler. Eski TeklifKalemId korunur; yeni tarafta baska bir kalem o
--    Id'yi kullaniyorsa (yeni programda acilmis kalem) o satir yeni Id alir.
DELETE FROM dbo.teklif_kalemleri WHERE TeklifId IN (SELECT TeklifId FROM #kalemFarkli);

SET IDENTITY_INSERT dbo.teklif_kalemleri ON;
INSERT INTO dbo.teklif_kalemleri
    (TeklifKalemId, TeklifId, UrunId, Adet, BirimFiyat, IndirimliBirimFiyat, ToplamTutar, MaliyetFiyati,
     UrunAciklamasi, UrunAciklamasiTr, UrunAciklamasiEn, ParaBirimi, Kur,
     EskiFiyatTL, EskiFiyatUSD, EskiFiyatEUR, Tamamlandi, UretimNotu)
SELECT o.TeklifUrunId, o.TeklifId, o.UrunId, o.Adet, o.BirimFiyat, o.IndirimliBirimFiyat, o.ToplamTutar,
       o.MaliyetFiyati, o.UrunAciklamasi, o.UrunAciklamasiTr, o.UrunAciklamasiEn, N'TL', 1,
       o.FiyatTL, o.FiyatUSD, o.FiyatEUR, ISNULL(o.Tamamlandi, 0), LEFT(o.UretimNotu, 1000)
FROM LiyaTeklifVeriTabani.dbo.teklif_urunleri o
JOIN #kalemYaz y ON y.TeklifId = o.TeklifId
WHERE NOT EXISTS (SELECT 1 FROM dbo.teklif_kalemleri k WHERE k.TeklifKalemId = o.TeklifUrunId);
SET IDENTITY_INSERT dbo.teklif_kalemleri OFF;

INSERT INTO dbo.teklif_kalemleri
    (TeklifId, UrunId, Adet, BirimFiyat, IndirimliBirimFiyat, ToplamTutar, MaliyetFiyati,
     UrunAciklamasi, UrunAciklamasiTr, UrunAciklamasiEn, ParaBirimi, Kur,
     EskiFiyatTL, EskiFiyatUSD, EskiFiyatEUR, Tamamlandi, UretimNotu)
SELECT o.TeklifId, o.UrunId, o.Adet, o.BirimFiyat, o.IndirimliBirimFiyat, o.ToplamTutar,
       o.MaliyetFiyati, o.UrunAciklamasi, o.UrunAciklamasiTr, o.UrunAciklamasiEn, N'TL', 1,
       o.FiyatTL, o.FiyatUSD, o.FiyatEUR, ISNULL(o.Tamamlandi, 0), LEFT(o.UretimNotu, 1000)
FROM LiyaTeklifVeriTabani.dbo.teklif_urunleri o
JOIN #kalemYaz y ON y.TeklifId = o.TeklifId
JOIN dbo.teklif_kalemleri k ON k.TeklifKalemId = o.TeklifUrunId AND k.TeklifId <> o.TeklifId;

-- 7) Toplamlar ve sevk bilgileri
UPDATE tt
SET IndirimliToplam = e.IndirimliToplam,
    KdvTutari       = e.KdvTutari,
    GenelToplam     = e.GenelToplam,
    PaketlemeUcreti = e.PaketlemeUcreti,
    TasimaUcreti    = e.TasimaUcreti
FROM dbo.teklif_toplamlari tt
JOIN #toplamFarkli f ON f.TeklifId = tt.TeklifId
JOIN #eskiToplam e ON e.TeklifId = tt.TeklifId;

INSERT INTO dbo.teklif_toplamlari
    (TeklifId, IndirimliToplam, KdvTutari, GenelToplam, PaketlemeUcreti, TasimaUcreti)
SELECT e.TeklifId, e.IndirimliToplam, e.KdvTutari, e.GenelToplam, e.PaketlemeUcreti, e.TasimaUcreti
FROM #eskiToplam e
JOIN #toplamFarkli f ON f.TeklifId = e.TeklifId
WHERE NOT EXISTS (SELECT 1 FROM dbo.teklif_toplamlari tt WHERE tt.TeklifId = e.TeklifId);

UPDATE sb
SET FaturaBasligi = e.FaturaBasligi, FaturaAdresi = e.FaturaAdresi,
    FaturaVergiDairesi = e.FaturaVergiDairesi, FaturaVergiNo = e.FaturaVergiNo,
    FaturaYetkili = e.FaturaYetkili, FaturaTelefon = e.FaturaTelefon, FaturaFax = e.FaturaFax,
    FaturaEposta = e.FaturaEposta, IrsaliyeBasligi = e.IrsaliyeBasligi, IrsaliyeAdresi = e.IrsaliyeAdresi,
    IrsaliyeVergiDairesi = e.IrsaliyeVergiDairesi, IrsaliyeVergiNo = e.IrsaliyeVergiNo,
    IrsaliyeYetkili = e.IrsaliyeYetkili, IrsaliyeTelefon = e.IrsaliyeTelefon,
    IrsaliyeEposta = e.IrsaliyeEposta, SiparisKdv = e.SiparisKdv, FaturaSekli = e.FaturaSekli,
    Garanti = e.Garanti, Teslimat = e.Teslimat, Odeme = e.Odeme, Nakliye = e.Nakliye,
    Kalibrasyon = e.Kalibrasyon, Egitim = e.Egitim, ReferansNumarasi = e.ReferansNumarasi,
    EkFaturaNotu = e.EkFaturaNotu, Aciklamalar = e.Aciklamalar, SiparisTarihi = e.SiparisTarihi
FROM dbo.sevk_bilgileri sb
JOIN #sevkFarkli f ON f.TeklifId = sb.TeklifId
JOIN #eskiSevk e ON e.TeklifId = sb.TeklifId;

INSERT INTO dbo.sevk_bilgileri
    (TeklifId, FaturaBasligi, FaturaAdresi, FaturaVergiDairesi, FaturaVergiNo, FaturaYetkili, FaturaTelefon,
     FaturaFax, FaturaEposta, IrsaliyeBasligi, IrsaliyeAdresi, IrsaliyeVergiDairesi, IrsaliyeVergiNo,
     IrsaliyeYetkili, IrsaliyeTelefon, IrsaliyeEposta, SiparisKdv, FaturaSekli, Garanti, Teslimat, Odeme,
     Nakliye, Kalibrasyon, Egitim, ReferansNumarasi, EkFaturaNotu, Aciklamalar, SiparisTarihi)
SELECT e.TeklifId, e.FaturaBasligi, e.FaturaAdresi, e.FaturaVergiDairesi, e.FaturaVergiNo, e.FaturaYetkili,
       e.FaturaTelefon, e.FaturaFax, e.FaturaEposta, e.IrsaliyeBasligi, e.IrsaliyeAdresi,
       e.IrsaliyeVergiDairesi, e.IrsaliyeVergiNo, e.IrsaliyeYetkili, e.IrsaliyeTelefon, e.IrsaliyeEposta,
       e.SiparisKdv, e.FaturaSekli, e.Garanti, e.Teslimat, e.Odeme, e.Nakliye, e.Kalibrasyon, e.Egitim,
       e.ReferansNumarasi, e.EkFaturaNotu, e.Aciklamalar, e.SiparisTarihi
FROM #eskiSevk e
JOIN #sevkFarkli f ON f.TeklifId = e.TeklifId
WHERE NOT EXISTS (SELECT 1 FROM dbo.sevk_bilgileri sb WHERE sb.TeklifId = e.TeklifId);

-- 8) Fatura isaretleme (db/33)
INSERT INTO dbo.sevk_bilgileri (TeklifId)
SELECT f.TeklifId FROM #fatura f
WHERE NOT EXISTS (SELECT 1 FROM dbo.sevk_bilgileri sb WHERE sb.TeklifId = f.TeklifId);

UPDATE sb
SET FaturaNo = f.YeniFaturaNo,
    FaturaTarihi = NULL,
    FaturaGuncelleyenId = NULL,
    FaturaGuncellemeTarihi = SYSDATETIME()
FROM dbo.sevk_bilgileri sb
JOIN #fatura f ON f.TeklifId = sb.TeklifId;

COMMIT TRANSACTION;

-- ---------------------------------------------------------------------------
-- D) DOGRULAMA: "Eski" ile "Yenide karsiligi olan" birebir esit olmali
-- ---------------------------------------------------------------------------
SELECT N'teklifler' AS Tablo,
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.teklifler) AS Eski,
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.teklifler o
        JOIN dbo.teklifler n ON n.TeklifId = o.TeklifId
                            AND o.OlusturmaTarihi = CAST(n.OlusturmaTarihi AS DATETIME)) AS YenideKarsiligiOlan
UNION ALL
SELECT N'teklif kalemleri (teklifi olan)',
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.teklif_urunleri k
        WHERE EXISTS (SELECT 1 FROM LiyaTeklifVeriTabani.dbo.teklifler t WHERE t.TeklifId = k.TeklifId)),
       (SELECT COUNT(*) FROM dbo.teklif_kalemleri k
        WHERE EXISTS (SELECT 1 FROM LiyaTeklifVeriTabani.dbo.teklifler t WHERE t.TeklifId = k.TeklifId))
UNION ALL
SELECT N'müşteriler',
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.musteriler),
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.musteriler o
        WHERE EXISTS (SELECT 1 FROM dbo.musteriler n WHERE n.MusteriId = o.MusteriId))
UNION ALL
SELECT N'ürünler',
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.urunler),
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.urunler o
        WHERE EXISTS (SELECT 1 FROM dbo.urunler n WHERE n.UrunId = o.UrunId))
UNION ALL
SELECT N'sevk bilgileri (teklif başına)',
       (SELECT COUNT(*) FROM #eskiSevk),
       (SELECT COUNT(*) FROM #eskiSevk e WHERE EXISTS (SELECT 1 FROM dbo.sevk_bilgileri sb WHERE sb.TeklifId = e.TeklifId));

PRINT N'Aktarım tamamlandı.';
GO
