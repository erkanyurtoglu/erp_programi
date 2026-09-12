-- ============================================================================
-- 05_teklif_durum_gecmisi.sql
--
-- Amac: Bir teklifin durumu artik TEK YONLU degil -- "Kabul Edildi" yapilmis bir
-- teklif, musteri sonradan vazgecerse "Reddedildi"ye, kararsiz kalirsa tekrar
-- "Beklemede"ye, "Tamamlandı" bile geri alinabilir hale geldi. Durum ileri geri
-- degisebildigi icin teklifler tablosundaki KabulTarihi / RedTarihi / TeslimTarihi
-- alanlari her degisimde yeniden yazilir (yani "en son gecerli" degeri tasirlar).
-- Gecmisin kaybolmamasi icin her durum degisimi burada AYRI bir satir olarak
-- loglanir: kim, ne zaman, hangi durumdan hangi duruma gecirdi ve (varsa) aciklama.
--
-- Bu script SADECE yeni bir tablo ekliyor; mevcut hicbir veriye dokunmuyor,
-- hicbir kaydi silmiyor/degistirmiyor. Zaten calisan LiyaErpVeriTabani uzerinde
-- SSMS'te calistirilabilir.
--
-- NOT: Bu tablo olusturulmasa da uygulama calisir -- durum degisimi yine yapilir,
-- sadece gecmis kaydi tutulmaz (Database::teklifDurumGuncelle icindeki loglama
-- "best effort"tur, hata verirse durum guncellemesini bozmaz).
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.objects
    WHERE object_id = OBJECT_ID('dbo.teklif_durum_gecmisi') AND type = 'U'
)
BEGIN
    CREATE TABLE dbo.teklif_durum_gecmisi (
        DurumGecmisiId  INT IDENTITY(1,1) PRIMARY KEY,
        TeklifId        INT NOT NULL REFERENCES dbo.teklifler(TeklifId) ON DELETE CASCADE,
        -- Degisimden ONCEKI durum. Teklif ilk kez olusturuldugunda log atilmadigi
        -- icin pratikte hep dolu gelir; yine de NULL'a acik birakildi.
        EskiDurum       NVARCHAR(50) NULL,
        YeniDurum       NVARCHAR(50) NOT NULL,
        -- "Reddedildi"ye gecerken girilen red sebebi; diger gecislerde NULL.
        Aciklama        NVARCHAR(500) NULL,
        -- Degisikligi yapan personel (oturumdaki kullanici). Bilinmiyorsa NULL.
        KullaniciId     INT NULL REFERENCES dbo.kullanicilar(KullaniciId),
        DegisiklikTarihi DATETIME2 NOT NULL DEFAULT SYSDATETIME()
    );

    CREATE INDEX IX_teklif_durum_gecmisi_TeklifId
        ON dbo.teklif_durum_gecmisi(TeklifId, DegisiklikTarihi DESC);
END
GO

PRINT N'teklif_durum_gecmisi tablosu olusturuldu (veya zaten mevcuttu).';
