-- ============================================================================
-- 23_ayar_degeri_uzun_metin.sql
--
-- dbo.ayarlar.Deger NVARCHAR(500) -> NVARCHAR(MAX).
--
-- Yonetim / Sistem Ayarlari'ndaki varsayilan satis sozlesmesi metinleri
-- (SATIS_SOZLESME_METNI_TR / _EN) 500 karaktere sigmaz. Mevcut degerlere
-- dokunulmaz; teklifler tablosu degismez.
--
-- Defalarca calistirilabilir.
-- Onkosul: db/17_satinalma_ve_cihaz_maliyetleri.sql (dbo.ayarlar)
-- ============================================================================
USE LiyaErpVeriTabani;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.ayarlar') AND name = 'Deger' AND max_length <> -1
)
BEGIN
    ALTER TABLE dbo.ayarlar ALTER COLUMN Deger NVARCHAR(MAX) NULL;
END
GO
