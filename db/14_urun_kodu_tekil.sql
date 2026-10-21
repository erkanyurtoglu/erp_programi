-- ============================================================================
-- 14_urun_kodu_tekil.sql
--
-- SORUN
-- dbo.urunler.UrunKodu uzerinde hicbir tekillik kisiti yok. Ayni kodla iki
-- urun kaydedilebiliyor; Teklif Ver ekranindaki aramada hangisinin secildigi
-- belirsiz kaliyor ve maliyet guncellemesi (urunMaliyetiGuncelle) yanlis
-- satira gidebiliyor.
--
-- NEDEN VERITABANI SEVIYESINDE TEKIL INDEKS YOK
-- Bu scriptin ilk hali filtreli bir UNIQUE indeks kurmaya calisiyordu:
--     WHERE UrunKodu IS NOT NULL AND UrunKodu <> N'' AND UrunKodu NOT LIKE N'MANUEL%'
-- Bu CALISMAZ ve "Incorrect syntax near the keyword 'LIKE'" hatasi verir:
-- filtered index yuklemi yalnizca basit karsilastirma operatorlerine izin
-- verir, LIKE kullanilamaz.
--
-- Kosulu atip filtresiz/dar bir indeks kurmak da MUMKUN DEGIL, cunku:
--
--   1) "MANUEL-<teklifId>" satirlari tasarim geregi kendi aralarinda
--      cakisir. Bu satirlar, sepete elle yazilan kalemler icin FOREIGN KEY
--      zorunlulugu yuzunden dbo.urunler'e yazilan teklife ozel gecici
--      kayitlardir ve INSERT, kalem dongusunun ICINDE calisir (bkz.
--      Database::teklifIceriginiYaz). Yani 3 manuel kalemli bir teklif,
--      ucu de ayni "MANUEL-<teklifId>" kodunu tasiyan 3 satir olusturur.
--      MANUEL satirlarini kapsayan bir tekil indeks, 2 veya daha fazla
--      manuel kalem iceren HER teklifin kaydedilmesini bozardi.
--
--   2) Hesaplanan (computed) kolon + filtreli indeks de cozmez: filtered
--      index yuklemi hesaplanan bir kolona referans veremez.
--
--   3) Filtresiz tekil indeks de cozmez: tekil indeks yalnizca TEK bir
--      NULL'a izin verir, oysa kodu girilmemis urunler (eski programdan
--      gocen kayitlarin bir kismi) ve MANUEL satirlari cok sayida NULL/
--      tekrarli deger uretir.
--
-- Kalici cozum, teklife ozel manuel kalemleri dbo.urunler'de tutmaktan
-- vazgecmek olurdu (ör. teklif_kalemleri.UrunId'yi nullable yapip aciklamayi
-- kalemde tutmak). Bu, teklif kaydetme/revizyon akisinin tamamini etkileyen
-- bir sema degisikligidir ve bu scriptin kapsami disindadir.
--
-- O ZAMAN TEKILLIK NEREDE SAGLANIYOR
-- UYGULAMA SEVIYESINDE: Database::urunEkle ve urunGuncelle, kaydetmeden once
-- urunKoduKullanimdaMi() ile kodun baska bir uruntde kullanilip
-- kullanilmadigini kontrol eder ve kullaniciya anlasilir bir mesaj gosterir
-- ("... kodu baska bir urunde kullaniliyor (<aciklama>)"). Ayrica "MANUEL"
-- oneki girise kapalidir.
--
-- BILINEN SINIR: kontrol ile INSERT arasinda (milisaniyeler) ayni kodu
-- kaydeden iki kullanici teorik olarak yarisabilir. Bu kurulumda (kucuk ekip,
-- tek sunucu) kabul edilmis bir risktir.
--
-- BU SCRIPT NE YAPAR
-- Hicbir sey degistirmez/silmez. Yalnizca MEVCUT mukerrer urun kodlarini
-- raporlar ki elle temizlenebilsinler. Tekrar tekrar guvenle calistirilabilir.
-- ============================================================================

USE LiyaErpVeriTabani;
GO

-- Mukerrer kullanilan urun kodlari (MANUEL satirlari ve kodsuz urunler haric).
SELECT UrunKodu,
       COUNT(*) AS KayitSayisi,
       STRING_AGG(CAST(UrunId AS NVARCHAR(20)), N', ') AS UrunIdleri
FROM dbo.urunler
WHERE UrunKodu IS NOT NULL
  AND LTRIM(RTRIM(UrunKodu)) <> N''
  AND UrunKodu NOT LIKE N'MANUEL%'
GROUP BY UrunKodu
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC, UrunKodu;
GO

-- Yukaridaki sorgu satir dondurduyse: ayni kodu tasiyan urunlerden hangisinin
-- dogru oldugunu Urunlerim ekranindan bakip karar verin, digerinin kodunu
-- duzeltin ya da onu arsivleyin ("Arşivle" butonu -- teklifte kullanilmis
-- urun silinemez, arsivlenir). Temizlik bittikten sonra bu scripti tekrar
-- calistirip hic satir donmedigini dogrulayin.
--
-- Bundan SONRA eklenecek/guncellenecek urunlerde mukerrer kod zaten uygulama
-- tarafindan engellenir.

PRINT N'Mukerrer urun kodu raporu tamamlandi (hicbir veri degistirilmedi).';
GO
