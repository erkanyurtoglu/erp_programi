-- ============================================================================
-- 10_teklif_no.sql
--
-- Amac: Kullanicinin gordugu teklif numarasini (Teklif No) sistemin ic anahtari
-- olan TeklifId'den AYIRMAK.
--
-- Sorun: Teklif No eskiden TeklifId'den turetiliyordu ("1203", revizyonda kok
-- teklifin id'si uzerinden "1203/Rev.2"). Ama her revizyon IDENTITY'den yeni bir
-- TeklifId harciyor; bu yuzden yeni tekliflerin numaralari atliyordu
-- (1203, 1204, 1206... -- 1205 bir revizyona gitmis).
--
-- TeklifNo : Kullaniciya, PDF'lere ve aramaya giden numara.
--            - Yeni (bagimsiz) teklif -- elle ya da "Kopya" ile -- en buyuk
--              TeklifNo + 1 alir. Revizyonlar numara HARCAMAZ, bu yuzden yeni
--              teklifler atlamadan sirayla ilerler.
--            - Revizyon, kok teklifin TeklifNo'sunu AYNEN tasir; surumu
--              RevizyonNo ayirir ("1203/Rev.2" = TeklifNo 1203, RevizyonNo 2).
--            Numarayi program atar (bkz. Database::teklifKaydet).
--
-- MEVCUT KAYITLAR: numaralari DEGISMEZ. Her satira bugune kadar gosterilen numara
-- (ISNULL(AnaTeklifId, TeklifId)) yazilir -- musteriye gitmis PDF'lerdeki
-- numaralar gecerli kalmali. Gecmisteki atlamalar bu yuzden oldugu gibi kalir;
-- sirali numaralandirma en buyuk mevcut numaradan itibaren baslar.
--
-- UX_teklifler_TeklifNo_Revizyon: ayni numara + revizyon ikilisi iki kez
-- verilemez (ayni anda kaydedilen iki teklife ayni numara verilmesine karsi
-- son guvence).
--
-- Script mevcut satirlara yalnizca TeklifNo yazar; baska hicbir veriye dokunmaz,
-- kayit silmez. Tekrar calistirilmasi zararsizdir.
--
-- NOT: Program sutunun VAR OLUP OLMADIGINI kendisi yokluyor (bkz.
-- Database::teklifNoKolonuVarMi). Script calistirilmadan da program calisir,
-- yalnizca numaralar eskisi gibi TeklifId'den turetilir (atlamalar devam eder).
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.teklifler') AND name = 'TeklifNo'
)
BEGIN
    ALTER TABLE dbo.teklifler ADD TeklifNo INT NULL;
END
GO

UPDATE dbo.teklifler
SET TeklifNo = ISNULL(AnaTeklifId, TeklifId)
WHERE TeklifNo IS NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.teklifler') AND name = 'UX_teklifler_TeklifNo_Revizyon'
)
BEGIN
    CREATE UNIQUE INDEX UX_teklifler_TeklifNo_Revizyon
        ON dbo.teklifler(TeklifNo, RevizyonNo)
        WHERE TeklifNo IS NOT NULL;
END
GO

PRINT N'TeklifNo alani eklendi ve mevcut teklifler numaralandi (veya zaten mevcuttu).';
