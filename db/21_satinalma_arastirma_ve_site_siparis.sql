-- ============================================================================
-- 21_satinalma_arastirma_ve_site_siparis.sql
--
-- Satinalma talebini fabrikadaki fiili duzene uyarlar:
--
--   * Kalemin nereden alinacagi cogu zaman BELLIDIR (tedarikci ya da isteyen
--     kisinin buldugu site). Bazen "sen bul" denir; o zaman satinalmaci
--     internette arastirir ve birden fazla fiyat not eder, en uygununu secer.
--     -> satinalma_talep_kalemleri.Arastirilacak
--
--   * Ayni siteden (direnc.net) farkli urunler alinabilir; urun sayfasi linki
--     firmaya degil FIYATA aittir. Fiyat notu da ("kargo dahil", "stokta 3
--     adet") fiyatin yanindadir.
--     -> satinalma_teklif_fiyatlari.UrunLinki, Notu
--     BirimFiyat = 0 "fiyat henuz alinmadi (tedarikciye soruldu)" demektir.
--
--   * Internet siparislerinde sitenin verdigi siparis numarasi ("kargom nerede"
--     sorusunda sitede aramak icin).
--     -> satinalmalar.SiteSiparisNo
--
-- Defalarca calistirilabilir, hicbir kaydi silmez.
-- Onkosul: db/20_satinalma_talep_teklif_siparis.sql
-- ============================================================================
USE LiyaErpVeriTabani;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF OBJECT_ID('dbo.satinalma_talep_kalemleri', 'U') IS NULL
BEGIN
    RAISERROR(N'Once 20_satinalma_talep_teklif_siparis.sql calistirilmali.', 16, 1);
    SET NOEXEC ON;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalma_talep_kalemleri') AND name = 'Arastirilacak')
BEGIN
    ALTER TABLE dbo.satinalma_talep_kalemleri ADD Arastirilacak BIT NOT NULL
        CONSTRAINT DF_satinalma_talep_kalemleri_Arastirilacak DEFAULT 0;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalma_teklif_fiyatlari') AND name = 'UrunLinki')
BEGIN
    ALTER TABLE dbo.satinalma_teklif_fiyatlari ADD UrunLinki NVARCHAR(1000) NULL;
    ALTER TABLE dbo.satinalma_teklif_fiyatlari ADD Notu      NVARCHAR(300)  NULL;
END
GO

-- Eski kayitlarda link firma uzerindeydi; o firmanin fiyatlarina tasinir
-- (firma kaydindaki link de yerinde kalir).
UPDATE fy SET UrunLinki = f.TeklifLinki
FROM dbo.satinalma_teklif_fiyatlari fy
JOIN dbo.satinalma_teklif_firmalari f ON f.TeklifFirmaId = fy.TeklifFirmaId
WHERE fy.UrunLinki IS NULL AND NULLIF(f.TeklifLinki, N'') IS NOT NULL;
GO

-- Bir kalem icin birden fazla fiyat (arastirma) varsa kalem arastirilacak
-- sayilir.
UPDATE tk SET Arastirilacak = 1
FROM dbo.satinalma_talep_kalemleri tk
WHERE tk.Arastirilacak = 0
  AND (SELECT COUNT(*) FROM dbo.satinalma_teklif_fiyatlari fy WHERE fy.TalepKalemId = tk.TalepKalemId) > 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'SiteSiparisNo')
BEGIN
    ALTER TABLE dbo.satinalmalar ADD SiteSiparisNo NVARCHAR(100) NULL;
END
GO

SET NOEXEC OFF;
GO
PRINT N'Satinalma arastirma / site siparis no alanlari hazir.';
