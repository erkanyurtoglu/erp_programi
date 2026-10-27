-- ============================================================================
-- 27_hatali_gocmen_maliyetleri_temizle.sql
--
-- db/26, eski veritabanindaki (LiyaTeklifVeriTabani) urunler.MaliyetFiyati
-- degerlerini dbo.urunler.GuncelMaliyetTL'ye tasidi. Bu degerlerin bir kismi
-- ESKI PROGRAMDA bozulmus: ~183 urunde maliyet satis fiyatindan yuksek (or.
-- LT-G0200 fiyat 36.540 TL, maliyet 247.231,50 TL; LT-G0207 fiyat 750 TL,
-- maliyet 122.660,96 TL). Degerler, urunun dovizli teklifteki fiyatinin TL
-- karsiligina benziyor -- eski programda dovizli teklifte maliyet kutusuna
-- fiyatin TL karsiligi yazilip kataloga kaydedilmis gorunuyor. Gocte satir
-- kaymasi YOK (kontrol edildi); hata eski verinin kendisinde.
--
-- Bu betik, maliyeti satis fiyatina ESIT ya da ondan YUKSEK olan urunlerin
-- maliyetini bosaltir -- yalnizca degeri hala db/26'nin tasidigi eski degerle
-- ayniysa (sonradan programda elle girilen maliyete dokunulmaz). Satis fiyati
-- 0 olan urunlere dokunulmaz (karsilastirilacak fiyat yok).
--
-- Bosaltilan degerler once dbo.urun_maliyet_yedek_27 tablosuna yazilir; geri
-- almak gerekirse:
--     UPDATE u SET u.GuncelMaliyetTL = y.EskiMaliyetTL
--     FROM dbo.urunler u JOIN dbo.urun_maliyet_yedek_27 y ON y.UrunId = u.UrunId
--     WHERE u.GuncelMaliyetTL IS NULL;
--
-- Defalarca calistirilabilir. Onkosul: db/26.
-- ============================================================================
USE LiyaErpVeriTabani;
GO

IF DB_ID(N'LiyaTeklifVeriTabani') IS NULL
BEGIN
    PRINT N'LiyaTeklifVeriTabani bulunamadi; hicbir sey yapilmadi.';
    RETURN;
END
GO

IF OBJECT_ID('dbo.urun_maliyet_yedek_27', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.urun_maliyet_yedek_27 (
        UrunId          INT NOT NULL PRIMARY KEY,
        UrunKodu        NVARCHAR(50) NULL,
        BirimFiyat      DECIMAL(18,2) NULL,
        EskiMaliyetTL   DECIMAL(18,2) NOT NULL,
        TemizlemeTarihi DATETIME2 NOT NULL DEFAULT SYSDATETIME()
    );
END
GO

BEGIN TRANSACTION;

INSERT INTO dbo.urun_maliyet_yedek_27 (UrunId, UrunKodu, BirimFiyat, EskiMaliyetTL)
SELECT y.UrunId, y.UrunKodu, y.BirimFiyat, y.GuncelMaliyetTL
FROM dbo.urunler y
JOIN LiyaTeklifVeriTabani.dbo.urunler e
  ON e.UrunId = y.UrunId AND ISNULL(e.UrunKodu, N'') = ISNULL(y.UrunKodu, N'')
WHERE y.BirimFiyat > 0
  AND y.GuncelMaliyetTL >= y.BirimFiyat
  AND y.GuncelMaliyetTL = e.MaliyetFiyati
  AND NOT EXISTS (SELECT 1 FROM dbo.urun_maliyet_yedek_27 k WHERE k.UrunId = y.UrunId);
PRINT CONCAT(N'Yedeklenen maliyet: ', @@ROWCOUNT);

UPDATE y SET y.GuncelMaliyetTL = NULL
FROM dbo.urunler y
JOIN dbo.urun_maliyet_yedek_27 k ON k.UrunId = y.UrunId
WHERE y.GuncelMaliyetTL = k.EskiMaliyetTL;
PRINT CONCAT(N'Bosaltilan maliyet: ', @@ROWCOUNT);

COMMIT TRANSACTION;
GO
