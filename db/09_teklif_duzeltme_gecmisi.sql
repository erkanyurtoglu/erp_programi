-- ============================================================================
-- 09_teklif_duzeltme_gecmisi.sql
--
-- Amac: "Duzeltme" ile "Revizyon"u birbirinden ayirmak.
--
--   Revizyon  : Musteriye gitmis teklifin YENI SURUMU (fiyat/sart degisti).
--               Yeni bir TeklifId + RevizyonNo olusur, eskisi "Revize Edildi"
--               olur (bkz. 04_teklif_revizyon.sql). Musterinin elindeki eski
--               belge ile sistemdeki kayit hep eslesir.
--   Duzeltme  : Kullanicinin kendi GIRIS HATASINI (yanlis firma, yanlis KDV,
--               yanlis indirim...) duzeltmesi. Ayni TeklifId YERINDE guncellenir,
--               revizyon numarasi artmaz.
--
-- Yerinde guncelleme eski icerigi ezdigi icin, her duzeltmeden HEMEN ONCE
-- teklifin o anki TAM hali (baslik + kalemler + toplamlar) JSON olarak bu
-- tabloya yazilir; ayrica kimin, ne zaman ve NEDEN duzelttigi saklanir.
-- Boylece hicbir veri kaybolmaz ve gerekirse eski hal geri okunabilir.
--
-- Duzeltme yalnizca durumu "Beklemede" olan ve revizyon zincirinin en guncel
-- uyesi olan teklifte yapilabilir (bkz. Database::teklifDuzelt). Kabul
-- edilmis / tamamlanmis / reddedilmis / revize edilmis teklif her zaman
-- revizyonla degisir.
--
-- ONEMLI: Durum gecmisinin aksine bu kayit "best effort" DEGILDIR. Tablo
-- yoksa program duzeltmeye IZIN VERMEZ (iz birakmadan ticari icerigin
-- ustune yazilmasin diye); bu durumda yalnizca revizyon kaydedilebilir.
--
-- Bu script SADECE yeni bir tablo ekliyor; mevcut hicbir veriye dokunmuyor,
-- hicbir kaydi silmiyor/degistirmiyor. Zaten calisan LiyaErpVeriTabani
-- uzerinde SSMS'te calistirilabilir.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.objects
    WHERE object_id = OBJECT_ID('dbo.teklif_duzeltme_gecmisi') AND type = 'U'
)
BEGIN
    CREATE TABLE dbo.teklif_duzeltme_gecmisi (
        DuzeltmeId      INT IDENTITY(1,1) PRIMARY KEY,
        TeklifId        INT NOT NULL REFERENCES dbo.teklifler(TeklifId) ON DELETE CASCADE,
        -- Kullanicinin girdigi duzeltme sebebi (zorunlu).
        Sebep           NVARCHAR(500) NOT NULL,
        -- Duzeltmeden ONCEKI tam icerik: teklifler satiri + "Kalemler" dizisi +
        -- "Toplamlar" nesnesi (SQL Server FOR JSON ciktisi).
        OncekiVeri      NVARCHAR(MAX) NOT NULL,
        KullaniciId     INT NULL REFERENCES dbo.kullanicilar(KullaniciId),
        DuzeltmeTarihi  DATETIME2 NOT NULL DEFAULT SYSDATETIME()
    );

    CREATE INDEX IX_teklif_duzeltme_gecmisi_TeklifId
        ON dbo.teklif_duzeltme_gecmisi(TeklifId, DuzeltmeTarihi DESC);
END
GO

PRINT N'teklif_duzeltme_gecmisi tablosu olusturuldu (veya zaten mevcuttu).';
