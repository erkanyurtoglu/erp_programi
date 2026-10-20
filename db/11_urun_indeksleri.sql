-- 11_urun_indeksleri.sql
--
-- SORUN
-- Urunlerim ekrani ve urun aramasi "ORDER BY UrunKodu" ile sayfalama yapiyor,
-- ama dbo.urunler tablosunda tek indeks UrunId uzerindeki CLUSTERED birincil
-- anahtardir. Bu yuzden her sayfa istegi tablonun TAMAMINI siralatiyordu.
--
-- Durum, UrunAciklamasi / UrunAciklamasiEn sutunlarinin nvarchar(MAX) (LOB)
-- olmasiyla agirlasiyor: siralama bu LOB degerlerini de tasimak zorunda kaliyor.
-- Olculen sure (2336 urun): 25 SANIYE. Sorgu UI thread'inde calistigi icin
-- program bu sure boyunca "Yanit Vermiyor" durumuna dusuyordu.
--
-- COZUM
-- Kod tarafinda sorgular "ertelenmis join" desenine cevrildi (once anahtarlari
-- sirala/sayfala, genis sutunlari sonra oku) -- bu tek basina sureyi ~42 ms'ye
-- indiriyor. Asagidaki indeks ise siralamayi tamamen ortadan kaldirip
-- OFFSET/FETCH'in dogrudan indeks uzerinde ilerlemesini saglar.
--
-- Guvenli ve geri alinabilir bir degisikliktir:
--   DROP INDEX IX_urunler_UrunKodu ON dbo.urunler;

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_urunler_UrunKodu'
                 AND object_id = OBJECT_ID(N'dbo.urunler'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_urunler_UrunKodu
        ON dbo.urunler (UrunKodu);
END
GO

-- Musteri ve personel listeleri de ad'a gore siralanip sayfalaniyor. Bu
-- tablolarda LOB sutunu olmadigi icin su an sorun cikarmiyorlar (olculen
-- sure 11-75 ms), ancak kayit sayisi buyudukce ayni darbogaz olusur.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_musteriler_FirmaAdi'
                 AND object_id = OBJECT_ID(N'dbo.musteriler'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_musteriler_FirmaAdi
        ON dbo.musteriler (FirmaAdi);
END
GO
