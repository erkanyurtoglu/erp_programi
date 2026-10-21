-- ============================================================================
-- 12_personel_sifre_salt.sql
--
-- SORUN
-- Sifreler duz SHA-256 olarak saklaniyordu (bkz. Database::sifreyiHashle).
-- Tuz (salt) olmadigi icin ayni sifreyi kullanan iki personelin SifreHash
-- degeri BIREBIR AYNI oluyordu: veritabanini goren biri kimlerin ayni sifreyi
-- kullandigini anlar, ayrica hazir "rainbow table" ile yaygin sifreler
-- dogrudan cozulebilir.
--
-- COZUM
-- Kullanici basina rastgele bir tuz sutunu. Hash artik SHA-256(salt + sifre).
--
-- GERIYE DONUK UYUMLU: SifreSalt NULL olan kayitlar "eski usul" (tuzsuz)
-- kabul edilir ve eskisi gibi dogrulanir; kullanici bir dahaki girisinde
-- sifresi SESSIZCE tuzlu hale yukseltilir (bkz. Database::girisYap --
-- goc donemindeki duz metin -> hash yukseltmesiyle ayni desen). Yani bu
-- script calistirildiktan sonra kimsenin sifresini sifirlamak GEREKMEZ.
--
-- Bu script SADECE yeni sutun ekler, mevcut veriye dokunmaz.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.kullanicilar') AND name = 'SifreSalt'
)
BEGIN
    ALTER TABLE dbo.kullanicilar ADD SifreSalt NVARCHAR(64) NULL;
END
GO

PRINT N'kullanicilar.SifreSalt alani eklendi (veya zaten mevcuttu).';
