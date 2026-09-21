-- ============================================================================
-- 07_teklif_kopya_kaynagi.sql
--
-- Amac: Giden/Alınan/Biten Tekliflerim'deki "Kopya" butonu icin. Satis
-- personeli ayni (veya cok benzer) icerikli teklifi farkli firmalara verebiliyor;
-- bunun icin var olan bir teklifin TUM icerigini (kalemler, fiyatlar, indirim/KDV,
-- teslimat sartlari, sozlesme metni) yeni bir teklif formuna kopyalayip
-- uzerinde degisiklik yaptiktan sonra BAGIMSIZ bir teklif olarak kaydedebiliyor.
--
-- Bu, REVIZYON DEGILDIR (bkz. 04_teklif_revizyon.sql):
--   Revizyon  : ayni musteriye verilen ayni teklifin yeni surumu. AnaTeklifId ile
--               koke baglanir ve onceki surumleri "Revize Edildi" yapar (gecersiz
--               kilar).
--   Kopya     : bastan bagimsiz, yepyeni bir teklif. AnaTeklifId NULL, RevizyonNo 0
--               kalir; kaynak teklifin DURUMU VE ICERIGI HIC DEGISMEZ, kaynak
--               gecersiz sayilmaz. Iki teklif ayni anda gecerli olabilir -- zaten
--               amac budur (farkli firmalara benzer teklifler).
--
-- KopyaKaynakTeklifId : Bu teklifin kopyalandigi teklifin TeklifId'si. Elle
--               olusturulan tekliflerde NULL kalir. Yalnizca izlenebilirlik
--               icindir (listede "#1203'ten kopya" bilgisi); hicbir is kuralini
--               tetiklemez.
--
-- Bilincli olarak FOREIGN KEY YOK: kaynak teklif silinebilir olmaya devam etmeli.
-- FK konulsa, kopyasi alinmis bir teklif "Sil" ile silinemezdi (ya da silme,
-- kopyayi da goturmeye calisirdi). Kaynak silinmisse kolonda artik var olmayan
-- bir id kalir; okuyan taraf bunu bir teklife baglayamazsa bilgi satirini
-- gostermez -- veri kaybi veya tutarsizlik olusmaz.
--
-- Bu script SADECE yeni sutun ekliyor (ALTER TABLE ... ADD), mevcut hicbir
-- veriye dokunmuyor, hicbir kaydi silmiyor/degistirmiyor. Zaten calisan
-- LiyaErpVeriTabani uzerinde SSMS'te calistirilabilir.
--
-- NOT: Program bu sutunun VAR OLUP OLMADIGINI kendisi yokluyor (bkz.
-- Database::kopyaKolonuVarMi). Script calistirilmadan da "Kopya" butonu calisir,
-- yalnizca "hangi tekliften kopyalandi" izi tutulmaz.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.teklifler') AND name = 'KopyaKaynakTeklifId'
)
BEGIN
    ALTER TABLE dbo.teklifler ADD KopyaKaynakTeklifId INT NULL;
END
GO

PRINT N'KopyaKaynakTeklifId alani eklendi (veya zaten mevcuttu).';
