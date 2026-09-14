-- ============================================================================
-- 06_teklif_uretim_notu.sql
--
-- Amac: Teklif notu ile uretim notunu birbirinden ayirmak. Eskiden tek bir
-- MusteriNotu alani vardi ve hem satis tarafinin teklife dusulen notlarini hem
-- de teknik ekibe verilen uretim PDF'ine basilan notu tasiyordu -- yani teklife
-- yazilan (fiyat, pazarlik, musteriyle ilgili ic) notlar uretimciye de gidiyordu.
--
-- MusteriNotu : Teklif notu. Yalnizca satis tarafinda gorunur; uretim PDF'ine
--               BASILMAZ.
-- UretimNotu  : Uretim notu. Uretim PDF'ine basilir.
--
-- Bu script SADECE yeni sutun ekliyor (ALTER TABLE ... ADD), mevcut hicbir
-- veriye dokunmuyor. Eski MusteriNotu degerleri bilincli olarak UretimNotu'na
-- KOPYALANMAZ: icerisinde uretimcinin gormemesi gereken teklif notlari olabilir.
-- Uretime gitmesi gereken bir not varsa ilgili teklifin Detay ekranindan
-- "Üretim Notu" alanina yazilmalidir.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.teklifler') AND name = 'UretimNotu'
)
BEGIN
    ALTER TABLE dbo.teklifler ADD UretimNotu NVARCHAR(1000) NULL;
END
GO

PRINT N'UretimNotu alani eklendi (veya zaten mevcuttu).';
