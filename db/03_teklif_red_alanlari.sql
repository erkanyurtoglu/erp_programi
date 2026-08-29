-- ============================================================================
-- 03_teklif_red_alanlari.sql
--
-- Amac: "Reddedildi" durumu icin opsiyonel bir red sebebi/yorum ve red tarihi
-- alani ekliyoruz. Bu script SADECE yeni sutun ekliyor (ALTER TABLE ... ADD),
-- mevcut hicbir veriye dokunmuyor, hicbir kaydi silmiyor/degistirmiyor.
-- Zaten calisan LiyaErpVeriTabani uzerinde SSMS'te calistirilabilir.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.teklifler') AND name = 'RedSebebi'
)
BEGIN
    ALTER TABLE dbo.teklifler ADD RedSebebi NVARCHAR(500) NULL;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.teklifler') AND name = 'RedTarihi'
)
BEGIN
    ALTER TABLE dbo.teklifler ADD RedTarihi DATETIME2 NULL;
END
GO

PRINT N'RedSebebi / RedTarihi alanlari eklendi (veya zaten mevcuttu).';
