-- ============================================================================
-- 34_personel_tema.sql
--
-- ISTEK
-- Her personel programi kendi istedigi temayla (koyu / acik) kullanabilsin;
-- yonetici bunu Yonetim > Personellerim > Personel Duzenle'den secebilsin.
--
-- COZUM
-- dbo.kullanicilar'a KoyuTema eklenir: 1 = koyu, 0 = acik, NULL = varsayilan
-- (koyu). Personel giris yapinca bu tema uygulanir; personel ekrandaki tema
-- anahtariyla kendi temasini degistirirse secimi buraya yazilir.
--
-- Script calistirilmamissa program eski gibi calisir: tema yalnizca o
-- bilgisayarda hatirlanir.
--
-- Bu script SADECE yeni sutun ekler, mevcut veriye dokunmaz.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.kullanicilar') AND name = 'KoyuTema'
)
BEGIN
    ALTER TABLE dbo.kullanicilar ADD KoyuTema BIT NULL;
END
GO

PRINT N'kullanicilar.KoyuTema alani eklendi (veya zaten mevcuttu).';
