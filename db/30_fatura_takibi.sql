-- ============================================================================
-- 30_fatura_takibi.sql
--
-- ISTEK
-- "Fatura edildi mi?" bilgisi eskiden irsaliye penceresindeki AÇIKLAMALAR
-- alanina serbest metin olarak yaziliyordu ("fatura edildi", "FT kesildi"...);
-- faturalanmamis teklifleri listelemek mumkun degildi.
--
-- COZUM
-- Sevk kaydina ayri alanlar eklenir: Irsaliye No, Fatura No, Fatura Tarihi ve
-- bunlari en son kimin ne zaman yazdigi. Fatura No dolu olan teklif
-- "Faturalandı" sayilir. Teklifin durumundan BAGIMSIZDIR: fatura kesilip cihaz
-- henuz teslim edilmemis olabilir; teklif otomatik "Tamamlandı" yapilmaz.
--
-- Bu alanlar teklif "Tamamlandı" olduktan sonra da yazilabilir (fatura
-- teslimden sonra kesilebilir); sevk kaydinin diger alanlari ise kilitlenir
-- (bkz. Database::faturaBilgisiKaydet).
--
-- Bu script SADECE yeni sutun ekler, mevcut veriye (AÇIKLAMALAR dahil)
-- dokunmaz. Birden fazla kez calistirilabilir.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.sevk_bilgileri') AND name = 'FaturaNo')
BEGIN
    ALTER TABLE dbo.sevk_bilgileri ADD
        IrsaliyeNo             NVARCHAR(50) NULL,
        FaturaNo               NVARCHAR(50) NULL,
        FaturaTarihi           DATE         NULL,
        FaturaGuncelleyenId    INT          NULL REFERENCES dbo.kullanicilar(KullaniciId),
        FaturaGuncellemeTarihi DATETIME2    NULL;
END
GO

PRINT N'sevk_bilgileri fatura takibi alanlari eklendi (veya zaten mevcuttu).';
