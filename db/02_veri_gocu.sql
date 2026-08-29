-- ============================================================================
-- 02_veri_gocu.sql
--
-- ONEMLI:
--  1) LiyaTeklifVeriTabani'nin TAM YEDEGINI aldiginizdan emin olun.
--  2) 01_yeni_veritabani_ve_sema.sql'i once calistirmis olmaniz gerekir.
--  3) Bu script LiyaTeklifVeriTabani'ne (eski veritabani) SADECE OKUMA (SELECT)
--     yapar, HICBIR SEKILDE yazma/silme islemi yapmaz. Eski veritabaniniz
--     bu script calistiktan sonra da aynen, hic degismeden durur.
--
-- NOT: teklif_urunleri.ParaBirimi kolonu kontrol edildi -- ornek 20 satirin
-- tamami 0.00, yani kullanilmayan/anlamsiz bir alan. Bu yuzden Kur icin notr
-- deger (1) verildi; FiyatTL/FiyatUSD/FiyatEUR kolonlari ise EskiFiyatTL/
-- EskiFiyatUSD/EskiFiyatEUR olarak (veri kaybi olmasin diye) oldugu gibi tasindi.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

-- ---------------------------------------------------------------------------
-- 1) Musteriler
-- ---------------------------------------------------------------------------
SET IDENTITY_INSERT dbo.musteriler ON;
INSERT INTO dbo.musteriler
    (MusteriId, FirmaAdi, FirmaAdresi, FirmaTelefonu, FirmaEposta, VergiDairesi, VergiNumarasi, IlgiliKisi, IlgiliKisiTelefonu, EklenmeTarihi)
SELECT
    MusteriId, FirmaAdi, FirmaAdresi, FirmaTelefonu, FirmaEposta, VergiDairesi, VergiNumarasi, IlgiliKisi, IlgiliKisiTelefonu, EklenmeTarihi
FROM LiyaTeklifVeriTabani.dbo.musteriler;
SET IDENTITY_INSERT dbo.musteriler OFF;

-- ---------------------------------------------------------------------------
-- 2) Personeller -> Kullanicilar (+ herkese gecici "Goc - Gecici Tam Yetkili" rolu)
-- ---------------------------------------------------------------------------
SET IDENTITY_INSERT dbo.kullanicilar ON;
INSERT INTO dbo.kullanicilar
    (KullaniciId, AdSoyad, KullaniciAdi, SifreHash, Telefon, Pozisyon, AktifMi, EklenmeTarihi)
SELECT
    PersonelId, AdSoyad, KullaniciAdi, Sifre, Telefon, Pozisyon, AktifMi, EklenmeTarihi
FROM LiyaTeklifVeriTabani.dbo.personeller;
SET IDENTITY_INSERT dbo.kullanicilar OFF;

INSERT INTO dbo.kullanici_rolleri (KullaniciId, RolId)
SELECT k.KullaniciId, r.RolId
FROM dbo.kullanicilar k
CROSS JOIN dbo.roller r
WHERE r.RolAdi = N'Göç - Geçici Tam Yetkili';

-- ---------------------------------------------------------------------------
-- 3) Urunler
-- ---------------------------------------------------------------------------
SET IDENTITY_INSERT dbo.urunler ON;
INSERT INTO dbo.urunler
    (UrunId, UrunKodu, Kategori, UrunAciklamasi, UrunAciklamasiEn, BirimFiyat, ParaBirimi, EklenmeTarihi)
SELECT
    UrunId, UrunKodu, Kategori, UrunAciklamasi, UrunAciklamasiEn, BirimFiyat, N'TL', EklenmeTarihi
FROM LiyaTeklifVeriTabani.dbo.urunler;
SET IDENTITY_INSERT dbo.urunler OFF;

-- ---------------------------------------------------------------------------
-- 4) Teklifler
-- ---------------------------------------------------------------------------
SET IDENTITY_INSERT dbo.teklifler ON;
INSERT INTO dbo.teklifler
    (TeklifId, MusteriId, KullaniciId, OlusturmaTarihi, GenelIndirimOrani, KdvOrani, Durum, MusteriNotu,
     ParaBirimi, Dil, SatisSozlesmesiMetni, IlgiliKisi, IlgiliKisiTelefonu, IlgiliKisiEposta,
     TeslimatSekli, TeslimatYeri, TeslimatTarihi, TeslimTarihi, KabulTarihi, UretimPdfTarihi)
SELECT
    TeklifId, MusteriId, PersonelId, OlusturmaTarihi, GenelIndirimOrani, KdvOrani, Durum, MusteriNotu,
    ParaBirimi, Dil, SatisSozlesmesiMetni, IlgiliKisi, IlgiliKisiTelefonu, IlgiliKisiEposta,
    TeslimatSekli, TeslimatYeri, TeslimatTarihi, TeslimTarihi, KabulTarihi, UretimPdfTarihi
FROM LiyaTeklifVeriTabani.dbo.teklifler;
SET IDENTITY_INSERT dbo.teklifler OFF;

-- ---------------------------------------------------------------------------
-- 5) Teklif kalemleri (teklif_urunleri -> teklif_kalemleri)
-- ---------------------------------------------------------------------------
SET IDENTITY_INSERT dbo.teklif_kalemleri ON;
INSERT INTO dbo.teklif_kalemleri
    (TeklifKalemId, TeklifId, UrunId, Adet, BirimFiyat, IndirimliBirimFiyat, ToplamTutar, MaliyetFiyati,
     UrunAciklamasi, UrunAciklamasiTr, UrunAciklamasiEn, ParaBirimi, Kur,
     EskiFiyatTL, EskiFiyatUSD, EskiFiyatEUR, Tamamlandi, UretimNotu)
SELECT
    TeklifUrunId, TeklifId, UrunId, Adet, BirimFiyat, IndirimliBirimFiyat, ToplamTutar, MaliyetFiyati,
    UrunAciklamasi, UrunAciklamasiTr, UrunAciklamasiEn,
    N'TL',   -- gercek para birimi kodu ayri tutulmamis; Teklif.ParaBirimi genel gecerli
    1,       -- ParaBirimi kolonu incelendi: her zaman 0.00, yani kullanilmamis/anlamsiz -> Kur icin notr deger
    FiyatTL, FiyatUSD, FiyatEUR,
    ISNULL(Tamamlandi, 0),
    UretimNotu
FROM LiyaTeklifVeriTabani.dbo.teklif_urunleri;
SET IDENTITY_INSERT dbo.teklif_kalemleri OFF;

-- ---------------------------------------------------------------------------
-- 6) Teklif toplamlari
-- ---------------------------------------------------------------------------
INSERT INTO dbo.teklif_toplamlari
    (TeklifId, IndirimliToplam, KdvTutari, GenelToplam, PaketlemeUcreti, TasimaUcreti)
SELECT
    TeklifId, IndirimliToplam, KdvTutari, GenelToplam, PaketlemeUcreti, TasimaUcreti
FROM LiyaTeklifVeriTabani.dbo.teklif_toplamlari;

-- ---------------------------------------------------------------------------
-- 7) Sevk bilgileri -- MUKERRER KAYIT TEMIZLIGI
-- Bir teklife ait birden fazla SevkBilgileri kaydi varsa, en son eklenen
-- (en yuksek SevkBilgileriId) kayit "gercek" kabul edilip tasinir; digerleri
-- ATILIR ama asagidaki SELECT ile hangi teklifler icin kac kayit atildigini
-- ONCE goreceksiniz.
-- ---------------------------------------------------------------------------

-- 7a) Once hangi tekliflerde mukerrer sevk kaydi var, gorelim (bilgi amacli):
SELECT
    TeklifNoID AS TeklifId,
    COUNT(*) AS ToplamSevkKaydi,
    COUNT(*) - 1 AS AtilacakMukerrerSayisi
FROM LiyaTeklifVeriTabani.dbo.SevkBilgileri
GROUP BY TeklifNoID
HAVING COUNT(*) > 1
ORDER BY ToplamSevkKaydi DESC;

-- 7b) Simdi tasima islemi: her teklif icin sadece en son (en yuksek ID'li) kayit.
WITH SonSevkKayitlari AS (
    SELECT
        sb.*,
        ROW_NUMBER() OVER (PARTITION BY sb.TeklifNoID ORDER BY sb.SevkBilgileriId DESC) AS SiraNo
    FROM LiyaTeklifVeriTabani.dbo.SevkBilgileri sb
)
INSERT INTO dbo.sevk_bilgileri
    (TeklifId, FaturaBasligi, FaturaAdresi, FaturaVergiDairesi, FaturaVergiNo, FaturaYetkili, FaturaTelefon,
     FaturaFax, FaturaEposta, IrsaliyeBasligi, IrsaliyeAdresi, IrsaliyeVergiDairesi, IrsaliyeVergiNo,
     IrsaliyeYetkili, IrsaliyeTelefon, IrsaliyeEposta, SiparisKdv, FaturaSekli, Garanti, Teslimat, Odeme,
     Nakliye, Kalibrasyon, Egitim, ReferansNumarasi, EkFaturaNotu, Aciklamalar, SiparisTarihi)
SELECT
    TeklifNoID, FaturaBasligi, FaturaAdresi, FaturaVergiDairesi, FaturaVergiNo, FaturaYetkili, FaturaTelefon,
    FaturaFax, FaturaEposta, IrsaliyeBasligi, IrsaliyeAdresi, IrsaliyeVergiDairesi, IrsaliyeVergiNo,
    IrsaliyeYetkili, IrsaliyeTelefon, IrsaliyeEposta, SiparisKdv, FaturaSekli, Garanti, Teslimat, Odeme,
    Nakliye, Kalibrasyon, Egitim, ReferansNumarasi, EkFaturaNotu, Aciklamalar, SiparisTarihi
FROM SonSevkKayitlari
WHERE SiraNo = 1;

-- ---------------------------------------------------------------------------
-- 8) DOGRULAMA RAPORU -- asagidaki sayilarin (sevk_bilgileri haric) BIREBIR
-- eslesmesi gerekir. sevk_bilgileri'nde "Yeni" sayisi "Eski"den kucukse, fark
-- yukaridaki 7a raporundaki "AtilacakMukerrerSayisi" toplamina esit olmalidir.
-- ---------------------------------------------------------------------------
SELECT 'musteriler' AS Tablo,
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.musteriler) AS Eski,
       (SELECT COUNT(*) FROM dbo.musteriler) AS Yeni
UNION ALL
SELECT 'kullanicilar (personeller)',
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.personeller),
       (SELECT COUNT(*) FROM dbo.kullanicilar)
UNION ALL
SELECT 'urunler',
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.urunler),
       (SELECT COUNT(*) FROM dbo.urunler)
UNION ALL
SELECT 'teklifler',
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.teklifler),
       (SELECT COUNT(*) FROM dbo.teklifler)
UNION ALL
SELECT 'teklif_kalemleri (teklif_urunleri)',
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.teklif_urunleri),
       (SELECT COUNT(*) FROM dbo.teklif_kalemleri)
UNION ALL
SELECT 'teklif_toplamlari',
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.teklif_toplamlari),
       (SELECT COUNT(*) FROM dbo.teklif_toplamlari)
UNION ALL
SELECT 'sevk_bilgileri (mukerrer temizlenmis olabilir)',
       (SELECT COUNT(*) FROM LiyaTeklifVeriTabani.dbo.SevkBilgileri),
       (SELECT COUNT(*) FROM dbo.sevk_bilgileri);
