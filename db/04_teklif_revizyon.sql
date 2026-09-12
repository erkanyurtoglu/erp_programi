-- ============================================================================
-- 04_teklif_revizyon.sql
--
-- Amac: Giden Tekliflerim'deki "Detay" -> "Revize Et" akisi icin, bir teklifin
-- revize edilmesi orijinal kaydi SILMEZ/UZERINE YAZMAZ; yerine ayni musteriye
-- ait YENI bir teklif satiri olusur ve AnaTeklifId ile kok teklife baglanir.
-- Boylece Giden Tekliflerim'de hem orijinal teklif hem de tum revizyonlari
-- ayri kayitlar olarak, PDF/gecmis kaybi olmadan gorulebilir.
--
-- AnaTeklifId  : Bu satirin revizyonu oldugu KOK teklifin TeklifId'si. Orijinal
--                (ilk) teklifte NULL kalir.
-- RevizyonNo   : 0 = orijinal teklif, 1/2/3... = o koke ait sirali revizyon
--                numarasi.
--
-- Bu script SADECE yeni sutun ekliyor (ALTER TABLE ... ADD), mevcut hicbir
-- veriye dokunmuyor, hicbir kaydi silmiyor/degistirmiyor. Zaten calisan
-- LiyaErpVeriTabani uzerinde SSMS'te calistirilabilir.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.teklifler') AND name = 'AnaTeklifId'
)
BEGIN
    ALTER TABLE dbo.teklifler ADD AnaTeklifId INT NULL REFERENCES dbo.teklifler(TeklifId);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.teklifler') AND name = 'RevizyonNo'
)
BEGIN
    ALTER TABLE dbo.teklifler ADD RevizyonNo INT NOT NULL DEFAULT 0;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.teklifler') AND name = 'IX_teklifler_AnaTeklifId'
)
BEGIN
    CREATE INDEX IX_teklifler_AnaTeklifId ON dbo.teklifler(AnaTeklifId);
END
GO

PRINT N'AnaTeklifId / RevizyonNo alanlari eklendi (veya zaten mevcuttu).';
