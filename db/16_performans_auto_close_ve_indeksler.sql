-- ======================================================================
-- 16 - PERFORMANS: AUTO_CLOSE kapatma + eksik indeksler
--
-- Programdaki "rastgele donma" sikayetlerinin ASIL sebebi burada.
--
-- 1) AUTO_CLOSE
--    Veritabani AUTO_CLOSE = ON ile olusturulmustu (SQL Server Express'te
--    bazi kurulum yollarinda varsayilan budur). Bu ayarla, SON baglanti
--    kapandigi anda SQL Server veritabanini TAMAMEN KAPATIR: dosyalari
--    birakir, bellekteki veri sayfalarini ve derlenmis sorgu planlarini
--    atar. Sonraki ilk baglanti ise veritabanini YENIDEN ACMAK zorunda
--    kalir -- dosya acma + kurtarma (recovery) + planlarin sifirdan
--    derlenmesi. Bu islem saniyeler, disk mesgulse ON SANIYELER surer.
--
--    Olculen etkisi (bkz. program gunlugu, 21.10.2026 17:19):
--      - 'rolListesiGetir' (tek satirlik kucuk bir SELECT): 27.718 ms
--      - 'Biten Tekliflerim' listesi:                        36.657 ms
--    Ikisi de AYNI ANDA bitti: ikisi de veritabaninin yeniden acilmasini
--    bekliyordu. Ayni sorgular, veritabani acikken olculdugunde 60-115 ms.
--
--    Bu ayarin kapatilmasi tamamen guvenlidir ve geri alinabilir; tek
--    etkisi, veritabaninin bellekte acik kalmasidir (bu veritabani icin
--    birkac on MB).
--
-- 2) teklif_kalemleri.TeklifId indeksi
--    Tabloda 59.706 satir var ve TeklifId uzerinde HIC indeks yoktu --
--    yalnizca TeklifKalemId'deki birincil anahtar. Teklif listesindeki
--    urun aramasi her teklif icin
--        EXISTS (SELECT 1 FROM teklif_kalemleri WHERE TeklifId = ...)
--    calistirdigi icin, bu tablo her seferinde bastan taraniyordu.
--
-- Calistirma: SQL Server Management Studio'da (ya da sqlcmd ile) bu
-- dosyayi acip calistirmak yeterlidir. Tekrar calistirilabilir.
-- ======================================================================

USE master;
GO

-- 1) Veritabani her zaman acik kalsin.
IF EXISTS (SELECT 1 FROM sys.databases
           WHERE name = N'LiyaErpVeriTabani' AND is_auto_close_on = 1)
BEGIN
    PRINT N'AUTO_CLOSE kapatiliyor...';
    ALTER DATABASE [LiyaErpVeriTabani] SET AUTO_CLOSE OFF WITH NO_WAIT;
END
ELSE
    PRINT N'AUTO_CLOSE zaten kapali.';
GO

USE [LiyaErpVeriTabani];
GO

-- 2) Teklif kalemlerini teklife gore aramak/okumak icin indeks.
--    UrunId de dahil edilir: EXISTS kosulu urunler tablosuna bu sutundan
--    baglanir, boylece indeks tek basina yeterli olur.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dbo.teklif_kalemleri')
                 AND name = N'IX_teklif_kalemleri_TeklifId')
BEGIN
    PRINT N'IX_teklif_kalemleri_TeklifId olusturuluyor...';
    CREATE NONCLUSTERED INDEX IX_teklif_kalemleri_TeklifId
        ON dbo.teklif_kalemleri (TeklifId)
        INCLUDE (UrunId);
END
ELSE
    PRINT N'IX_teklif_kalemleri_TeklifId zaten var.';
GO

-- 3) Sevk bilgisi, teklif listesinde her satir icin TeklifId'ye gore
--    okunur (OUTER APPLY ... ORDER BY SevkBilgileriId DESC).
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dbo.sevk_bilgileri')
                 AND name = N'IX_sevk_bilgileri_TeklifId')
BEGIN
    PRINT N'IX_sevk_bilgileri_TeklifId olusturuluyor...';
    CREATE NONCLUSTERED INDEX IX_sevk_bilgileri_TeklifId
        ON dbo.sevk_bilgileri (TeklifId, SevkBilgileriId DESC);
END
ELSE
    PRINT N'IX_sevk_bilgileri_TeklifId zaten var.';
GO

PRINT N'16 numarali performans scripti tamamlandi.';
GO
