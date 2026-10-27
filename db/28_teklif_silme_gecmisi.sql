-- ============================================================================
-- 28_teklif_silme_gecmisi.sql
--
-- Amac: Silinen tekliflerin izini tutmak.
--
-- Teklif silindiginde kalemleri, toplamlari, sevk bilgileri, durum gecmisi
-- (05) ve duzeltme gecmisi (09) ON DELETE CASCADE ile birlikte gider; eskiden
-- kimin, hangi teklifi, ne zaman sildigi de hicbir yerde kalmiyordu.
--
-- Bu tablo teklife FOREIGN KEY ile BAGLI DEGILDIR (aksi halde o da silinirdi).
-- Silmeden HEMEN ONCE, ayni transaction icinde teklifin tam hali (baslik +
-- kalemler + toplamlar + sevk + durum/duzeltme gecmisi) JSON olarak yazilir.
--
-- ONEMLI: Duzeltme gecmisi gibi bu kayit da "best effort" DEGILDIR. Tablo
-- yoksa ya da iz yazilamazsa program teklifi SILMEZ (bkz. Database::teklifSil).
--
-- Bu script SADECE yeni bir tablo ekliyor; mevcut hicbir veriye dokunmuyor.
-- Birden fazla kez calistirilabilir.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.objects
    WHERE object_id = OBJECT_ID('dbo.teklif_silme_gecmisi') AND type = 'U'
)
BEGIN
    CREATE TABLE dbo.teklif_silme_gecmisi (
        SilmeId         INT IDENTITY(1,1) PRIMARY KEY,
        -- Silinen teklifin ic anahtari; FK YOK (bkz. ustteki not).
        TeklifId        INT NOT NULL,
        -- Kullanicinin gordugu numara ("1203", "1203/Rev.2"): TeklifId tek
        -- basina okunakli degildir.
        TeklifNo        NVARCHAR(30) NOT NULL,
        FirmaAdi        NVARCHAR(500) NULL,
        -- Silindigi andaki durum.
        Durum           NVARCHAR(50) NULL,
        -- Silinmeden ONCEKI tam icerik (SQL Server FOR JSON ciktisi).
        SilinenVeri     NVARCHAR(MAX) NOT NULL,
        KullaniciId     INT NULL REFERENCES dbo.kullanicilar(KullaniciId),
        SilmeTarihi     DATETIME2 NOT NULL DEFAULT SYSDATETIME()
    );

    CREATE INDEX IX_teklif_silme_gecmisi_Tarih
        ON dbo.teklif_silme_gecmisi(SilmeTarihi DESC);
END
GO

PRINT N'teklif_silme_gecmisi tablosu olusturuldu (veya zaten mevcuttu).';
