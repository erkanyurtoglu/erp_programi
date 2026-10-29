-- ============================================================================
-- 29_personel_sifre_gorunur.sql
--
-- ISTEK
-- Personel sifresini unuttugunda yonetici Personel Duzenle ekranindan bakip
-- soyleyebilsin.
--
-- COZUM
-- Giris dogrulamasi eskisi gibi tuzlu hash ile (SifreHash + SifreSalt) yapilir.
-- Yanina sifrenin GERI ACILABILIR bir kopyasi eklenir:
-- ENCRYPTBYPASSPHRASE(anahtar, sifre). Anahtar programin icindedir (bkz.
-- Database.cpp SIFRE_GORUNTULEME_ANAHTARI); kopyayi yalnizca Yonetim
-- modulunde duzenleme yetkisi olan acabilir (Database::personelSifresiGetir).
--
-- Mevcut sifreler hash'ten geri cevrilemez: personelin kopyasi, bir sonraki
-- girisinde ya da yonetici ona yeni sifre verdiginde dolar. Gocten gelen ve
-- henuz hashlenmemis sifreler zaten okunabilir durumdadir.
--
-- Bu script SADECE yeni sutun ekler, mevcut veriye dokunmaz.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.kullanicilar') AND name = 'SifreSifreli'
)
BEGIN
    ALTER TABLE dbo.kullanicilar ADD SifreSifreli VARBINARY(512) NULL;
END
GO

PRINT N'kullanicilar.SifreSifreli alani eklendi (veya zaten mevcuttu).';
