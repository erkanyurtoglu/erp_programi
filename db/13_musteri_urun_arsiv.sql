-- ============================================================================
-- 13_musteri_urun_arsiv.sql
--
-- SORUN
-- Personellerde kalici silme yerine AktifMi bayragi kullaniliyor (gecmis
-- tekliflerin KullaniciId referansi kirilmasin diye). Musteri ve urunde ise
-- gercek DELETE var; teklifler.MusteriId ve teklif_kalemleri.UrunId FK'lari
-- ON DELETE CASCADE olmadigi icin -- ki bilerek oyle -- bir kez teklifte
-- kullanilmis musteri/urun ARTIK HIC SILINEMIYOR. Sonuc: katalog
-- temizlenemiyor, kullanilmayan eski urunler listede ve urun aramasinda
-- birikmeye devam ediyor.
--
-- COZUM
-- Personeldeki deseni musteri ve urune de getiriyoruz: "Arsivle". Arsivlenen
-- kayit listelerde ve Teklif Ver ekranindaki canli aramada gorunmez, ama
-- satiri yerinde durdugu icin GECMIS TEKLIFLER hic etkilenmez. Istenirse
-- "Arsivi goster" ile bulunup geri alinir.
--
-- Hicbir teklifte kullanilmamis bir kayit icin kalici silme imkani
-- KORUNUR (bkz. Database::musteriSil / urunSil).
--
-- Bu script SADECE yeni sutun + indeks ekler, mevcut veriye dokunmaz.
-- Tum mevcut kayitlar DEFAULT 1 ile "aktif" olarak isaretlenir.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.musteriler') AND name = 'AktifMi'
)
BEGIN
    ALTER TABLE dbo.musteriler ADD AktifMi BIT NOT NULL CONSTRAINT DF_musteriler_AktifMi DEFAULT 1;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.urunler') AND name = 'AktifMi'
)
BEGIN
    ALTER TABLE dbo.urunler ADD AktifMi BIT NOT NULL CONSTRAINT DF_urunler_AktifMi DEFAULT 1;
END
GO

-- Listeler ve canli arama artik "WHERE AktifMi = 1 AND ... ORDER BY <ad>"
-- seklinde calisiyor; 11 numarali scriptteki indeksleri bu kolonu kapsayacak
-- sekilde yenileyip siralamayi yine indeksten karsiliyoruz.
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = N'IX_urunler_UrunKodu' AND object_id = OBJECT_ID(N'dbo.urunler'))
BEGIN
    DROP INDEX IX_urunler_UrunKodu ON dbo.urunler;
END
GO

CREATE NONCLUSTERED INDEX IX_urunler_AktifMi_UrunKodu
    ON dbo.urunler (AktifMi, UrunKodu);
GO

IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = N'IX_musteriler_FirmaAdi' AND object_id = OBJECT_ID(N'dbo.musteriler'))
BEGIN
    DROP INDEX IX_musteriler_FirmaAdi ON dbo.musteriler;
END
GO

CREATE NONCLUSTERED INDEX IX_musteriler_AktifMi_FirmaAdi
    ON dbo.musteriler (AktifMi, FirmaAdi);
GO

PRINT N'musteriler.AktifMi / urunler.AktifMi alanlari ve indeksleri eklendi.';
