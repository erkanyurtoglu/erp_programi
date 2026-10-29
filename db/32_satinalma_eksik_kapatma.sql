-- ============================================================================
-- 32_satinalma_eksik_kapatma.sql
--
-- ISTEK
-- "Kısmi Teslim" kalan siparis kapatilamiyordu: 10 istenip 6 gelince kalan 4
-- hic gelmeyecekse siparis ve talep sonsuza kadar acik listede kaliyordu.
-- Artik eksik kalan miktar sebebiyle kapatilir; eksik miktar istenirse
-- talepte yeni bir kalem olarak yeniden acilir (baska yerden alinmak uzere).
--
--   dbo.satinalmalar
--     EksikKapatmaSebebi / EksikKapatmaTarihi / EksikKapatanKullaniciId
--         Doluysa siparis eksik gelmis ve kalan beklenmeden kapatilmistir
--         (Durum = 'Teslim Alındı').
--     TeslimOncekiDurum
--         Teslim alinmadan onceki durum ('Sipariş Verildi' / 'Kargoda');
--         "Teslimi Geri Al" siparisi bu duruma dondurur.
--   dbo.satinalma_talep_kalemleri
--     EksikKaynakSatinalmaId
--         Kalem, bu siparisin eksik gelen miktari icin acildi.
--
-- Defalarca calistirilabilir. Onkosul: db/21_satinalma_arastirma_ve_site_siparis.sql
-- ============================================================================
USE LiyaErpVeriTabani;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'EksikKapatmaTarihi')
BEGIN
    ALTER TABLE dbo.satinalmalar ADD
        EksikKapatmaSebebi      NVARCHAR(500) NULL,
        EksikKapatmaTarihi      DATETIME2     NULL,
        EksikKapatanKullaniciId INT           NULL
            CONSTRAINT FK_satinalmalar_EksikKapatan REFERENCES dbo.kullanicilar(KullaniciId);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'TeslimOncekiDurum')
BEGIN
    ALTER TABLE dbo.satinalmalar ADD TeslimOncekiDurum NVARCHAR(30) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalma_talep_kalemleri') AND name = 'EksikKaynakSatinalmaId')
BEGIN
    ALTER TABLE dbo.satinalma_talep_kalemleri ADD EksikKaynakSatinalmaId INT NULL
        CONSTRAINT FK_satinalma_talep_kalemleri_EksikKaynak REFERENCES dbo.satinalmalar(SatinalmaId);
END
GO

PRINT N'Satinalma eksik kapatma alanlari hazir.';
GO
