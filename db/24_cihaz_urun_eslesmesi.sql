-- ============================================================================
-- 24_cihaz_urun_eslesmesi.sql
--
-- dbo.cihazlar'a UrunId eklenir: cihaz maliyet kartinin urun katalogundaki
-- (Urunlerim) karsiligi. Yalnizca KARSILASTIRMA icindir -- cihazin hesaplanan
-- satis fiyati katalogdakinden farkliysa ekranda uyari cikar; katalog fiyati
-- kendiliginden degismez.
--
-- Yalnizca yeni sutun ekler; mevcut veriye dokunmaz. Defalarca calistirilabilir.
-- Onkosul: db/17_satinalma_ve_cihaz_maliyetleri.sql (dbo.cihazlar)
-- ============================================================================
USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.cihazlar') AND name = 'UrunId')
BEGIN
    ALTER TABLE dbo.cihazlar ADD UrunId INT NULL
        CONSTRAINT FK_cihazlar_UrunId REFERENCES dbo.urunler(UrunId);
END
GO
