-- ============================================================================
-- 15_tedarikci.sql
--
-- Satinalma modulu, 1. adim: Tedarikcilerim ekrani icin tedarikciler tablosuna
--   * AktifMi            : musteri/urunlerdeki gibi "Arsivle" (silmek yerine gizle)
--   * IlgiliKisiTelefonu : musteri formuyla ayni alan
-- ekler, ve siralama/arama icin bir indeks kurar.
--
-- SADECE yeni sutun + indeks ekler, mevcut veriye dokunmaz, hicbir kaydi
-- silmez. Tekrar calistirilmasi zararsizdir.
-- ============================================================================
USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.tedarikciler') AND name = 'AktifMi'
)
BEGIN
    ALTER TABLE dbo.tedarikciler
        ADD AktifMi BIT NOT NULL CONSTRAINT DF_tedarikciler_AktifMi DEFAULT 1;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.tedarikciler') AND name = 'IlgiliKisiTelefonu'
)
BEGIN
    ALTER TABLE dbo.tedarikciler ADD IlgiliKisiTelefonu NVARCHAR(50) NULL;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_tedarikciler_AktifMi_FirmaAdi' AND object_id = OBJECT_ID(N'dbo.tedarikciler')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_tedarikciler_AktifMi_FirmaAdi
        ON dbo.tedarikciler (AktifMi, FirmaAdi);
END
GO

PRINT N'tedarikciler.AktifMi / IlgiliKisiTelefonu alanlari ve indeks eklendi (veya zaten mevcuttu).';
GO
