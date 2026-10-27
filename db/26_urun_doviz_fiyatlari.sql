-- ============================================================================
-- 26_urun_doviz_fiyatlari.sql
--
-- Urunun TL / USD / EUR satis fiyatlari BIRBIRINDEN BAGIMSIZDIR: 1.000 TL'lik
-- urun yurt disina 60 $'a satilabilir. Doviz fiyati TL fiyatinin kura
-- bolunmesiyle bulunmaz; teklifte secilen para biriminin fiyati dogrudan
-- kullanilir. Eski programda (LiyaTeklifVeriTabani) bu fiyatlar FiyatTL /
-- FiyatUSD / FiyatEUR sutunlarindaydi; db/02 gocu yalnizca BirimFiyat'i
-- tasidigi icin USD/EUR fiyatlari ve urun maliyetleri kaybolmustu.
--
--   1) dbo.urunler'e FiyatUSD, FiyatEUR eklenir (NULL = o para biriminde
--      fiyat girilmemis; teklifte kalem 0 gelir ve elle girilir).
--   2) Eski veritabanindan, ayni UrunId + UrunKodu'na sahip urunlere:
--        * FiyatUSD / FiyatEUR (yalnizca > 0 olanlar, yeni tarafta bossa),
--        * TL fiyati: eski programda TL tekliflerde kullanilan FiyatTL
--          (yalnizca > 0 ise ve BirimFiyat gocten beri DEGISMEMISSE --
--          yani hala eski BirimFiyat ile ayniysa),
--        * Maliyet: MaliyetFiyati -> GuncelMaliyetTL (yalnizca yeni tarafta bossa).
--
-- Sonradan programda girilmis hicbir deger ezilmez. Defalarca calistirilabilir.
-- Eski veritabani sunucuda yoksa yalnizca sutunlar eklenir.
-- ============================================================================
USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.urunler') AND name = 'FiyatUSD')
    ALTER TABLE dbo.urunler ADD FiyatUSD DECIMAL(18,2) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.urunler') AND name = 'FiyatEUR')
    ALTER TABLE dbo.urunler ADD FiyatEUR DECIMAL(18,2) NULL;
GO

IF DB_ID(N'LiyaTeklifVeriTabani') IS NOT NULL
BEGIN
    BEGIN TRANSACTION;

    -- Doviz fiyatlari
    UPDATE y SET y.FiyatUSD = e.FiyatUSD
    FROM dbo.urunler y
    JOIN LiyaTeklifVeriTabani.dbo.urunler e
      ON e.UrunId = y.UrunId AND ISNULL(e.UrunKodu, N'') = ISNULL(y.UrunKodu, N'')
    WHERE y.FiyatUSD IS NULL AND e.FiyatUSD > 0;
    PRINT CONCAT(N'USD fiyati tasinan urun: ', @@ROWCOUNT);

    UPDATE y SET y.FiyatEUR = e.FiyatEUR
    FROM dbo.urunler y
    JOIN LiyaTeklifVeriTabani.dbo.urunler e
      ON e.UrunId = y.UrunId AND ISNULL(e.UrunKodu, N'') = ISNULL(y.UrunKodu, N'')
    WHERE y.FiyatEUR IS NULL AND e.FiyatEUR > 0;
    PRINT CONCAT(N'EUR fiyati tasinan urun: ', @@ROWCOUNT);

    -- TL fiyati: eski programin TL tekliflerde kullandigi FiyatTL. BirimFiyat
    -- gocten beri degistirilmemisse (eski BirimFiyat ile ayniysa) duzeltilir.
    UPDATE y SET y.BirimFiyat = e.FiyatTL
    FROM dbo.urunler y
    JOIN LiyaTeklifVeriTabani.dbo.urunler e
      ON e.UrunId = y.UrunId AND ISNULL(e.UrunKodu, N'') = ISNULL(y.UrunKodu, N'')
    WHERE e.FiyatTL > 0
      AND ISNULL(y.BirimFiyat, 0) = ISNULL(e.BirimFiyat, 0)
      AND ISNULL(y.BirimFiyat, 0) <> e.FiyatTL;
    PRINT CONCAT(N'TL fiyati FiyatTL ile duzeltilen urun: ', @@ROWCOUNT);

    -- Maliyet
    UPDATE y SET y.GuncelMaliyetTL = e.MaliyetFiyati
    FROM dbo.urunler y
    JOIN LiyaTeklifVeriTabani.dbo.urunler e
      ON e.UrunId = y.UrunId AND ISNULL(e.UrunKodu, N'') = ISNULL(y.UrunKodu, N'')
    WHERE y.GuncelMaliyetTL IS NULL AND e.MaliyetFiyati > 0;
    PRINT CONCAT(N'Maliyeti tasinan urun: ', @@ROWCOUNT);

    COMMIT TRANSACTION;
END
ELSE
    PRINT N'LiyaTeklifVeriTabani bulunamadi; yalnizca sutunlar eklendi.';
GO
