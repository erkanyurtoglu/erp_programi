-- ============================================================================
-- 08_teklif_kalem_uretim_takibi.sql
--
-- Amac: Uretim takibini TEKLIF basindan KALEM basina indirmek. Bir teklifte
-- birden fazla urun oldugunda, uretim/sevkiyat asamasinda hangi urunun bittigi
-- ve hangi urunde ozel bir not oldugu satir satir izlenebilsin.
--
-- Oncesinde yalnizca teklifin TAMAMI icin tek bir uretim notu vardi
-- (dbo.teklifler.UretimNotu, bkz. 06_teklif_uretim_notu.sql) ve "tamamlandi"
-- bilgisi hic yoktu -- 5 urunluk bir teklifte 3'unun bittigi programda
-- gorunmuyordu.
--
-- Tamamlandi  : Bu KALEMIN uretimi bitti mi? Uretim formunda satirin "Durum"
--               sutununda gorunur.
-- UretimNotu  : Bu KALEME ozel uretim notu (olcu, malzeme, oncelik...). Uretim
--               formunda ilgili satirin altina basilir. Teklifin GENEL uretim
--               notu (dbo.teklifler.UretimNotu) bundan bagimsizdir ve olduğu
--               gibi kalir -- ikisi birlikte kullanilir.
--
-- ONEMLI: Bu iki sutun 01_yeni_veritabani_ve_sema.sql ile olusturulan
-- veritabanlarinda ZATEN VARDIR (eski sistemden gocurulen veri kaybolmasin diye
-- bastan tanimlanmislardi, bkz. 02_veri_gocu.sql) -- ama bugune kadar program
-- tarafindan hic okunmuyor/yazilmiyorlardi. Bu script yalnizca sutunlarin
-- herhangi bir sebeple eksik oldugu kurulumlar icin bir guvencedir: sutun
-- varsa HICBIR SEY yapmaz, mevcut veriye dokunmaz.
--
-- Kilit kurali (programda uygulanir, bkz. Database::teklifKalemTamamlandiGuncelle):
-- teklif "Tamamlandı" durumuna gectikten sonra bu iki alan da degistirilemez --
-- planlanan teslim tarihi ve teklifin genel uretim notuyla ayni mantik.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.teklif_kalemleri') AND name = 'Tamamlandi'
)
BEGIN
    ALTER TABLE dbo.teklif_kalemleri ADD Tamamlandi BIT NOT NULL DEFAULT 0;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.teklif_kalemleri') AND name = 'UretimNotu'
)
BEGIN
    ALTER TABLE dbo.teklif_kalemleri ADD UretimNotu NVARCHAR(1000) NULL;
END
GO

PRINT N'teklif_kalemleri.Tamamlandi / UretimNotu alanlari hazir (zaten mevcut olabilir).';
