-- ============================================================================
-- 33_eski_faturalari_isaretle.sql
--
-- ISTEK
-- db/30'dan once "fatura edildi" bilgisi irsaliye penceresindeki AÇIKLAMALAR
-- alanina serbest metinle yaziliyordu (ya da hic yazilmiyordu). Bu kayitlarin
-- Fatura No'su bos oldugu icin Muhasebe kartinda "Faturalanacak" gorunuyorlar.
--
-- COZUM
-- Fatura No'su bos eski kayitlar tek tek ayiklanmaz:
--   * Tamamlandı: hepsi "Faturalandı" sayilir.
--       - AÇIKLAMALAR'da faturanin kesildigi yaziyorsa ("FAT.İRS.KESİLDİ",
--         "FATURA KESİLDİ", "FAT.EDİLDİ", "faturalandı") -> N'ESKİ KAYIT'
--       - yazmiyorsa                                     -> N'BİLİNMİYOR'
--   * Kabul Edildi (siparis hala acik): yalnizca kesildigi yaziyorsa
--     N'ESKİ KAYIT'; digerleri "Faturalanacak" kalir -- faturasi gercekten
--     bekleniyor olabilir ("faturalandırılacak").
-- Fatura Tarihi bos kalir (gercek tarih bilinmiyor).
--
-- KULLANIM
--   1) Oldugu gibi calistirin: yalnizca ONIZLEME gelir, veri degismez.
--   2) Uygunsa @Uygula = 1 yapip yeniden calistirin.
--
-- Geri almak icin:
--   UPDATE dbo.sevk_bilgileri SET FaturaNo = NULL, FaturaGuncelleyenId = NULL,
--          FaturaGuncellemeTarihi = NULL
--   WHERE FaturaNo IN (N'ESKİ KAYIT', N'BİLİNMİYOR');
--   (BİLİNMİYOR icin yeni olusturulan bos sevk kayitlari kalir; zarari yoktur.)
--
-- Onkosul: db/30_fatura_takibi.sql. Defalarca calistirilabilir.
-- ============================================================================
USE LiyaErpVeriTabani;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

DECLARE @Uygula BIT = 0;   -- 1 = isaretle, 0 = yalnizca onizleme

IF OBJECT_ID('tempdb..#aday') IS NOT NULL DROP TABLE #aday;

-- i/ı/İ/I yazim farki icin o harfler "_" ile eslenir (harmanlamadan bagimsiz).
SELECT t.TeklifId, ISNULL(t.TeklifNo, ISNULL(t.AnaTeklifId, t.TeklifId)) AS TeklifNo, t.RevizyonNo,
       m.FirmaAdi, t.Durum, t.KabulTarihi, sb.Aciklamalar,
       CASE WHEN UPPER(sb.Aciklamalar) LIKE N'%FA%KES_LD_%'
              OR UPPER(sb.Aciklamalar) LIKE N'%FA%ED_LD_%'
              OR UPPER(sb.Aciklamalar) + N' ' LIKE N'%FATURALAND_[^R]%'
            THEN N'ESKİ KAYIT' ELSE N'BİLİNMİYOR' END AS YeniFaturaNo
INTO #aday
FROM dbo.teklifler t
INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId
LEFT JOIN dbo.sevk_bilgileri sb ON sb.TeklifId = t.TeklifId
WHERE t.Durum IN (N'Kabul Edildi', N'Tamamlandı')
  AND NULLIF(LTRIM(RTRIM(sb.FaturaNo)), N'') IS NULL;

-- Acik siparis + bilgi yok: Faturalanacak'ta kalir.
DELETE FROM #aday WHERE Durum = N'Kabul Edildi' AND YeniFaturaNo = N'BİLİNMİYOR';

-- ONIZLEME
SELECT YeniFaturaNo, TeklifNo, RevizyonNo, FirmaAdi, Durum, KabulTarihi, Aciklamalar
FROM #aday
ORDER BY YeniFaturaNo, KabulTarihi DESC, TeklifId DESC;

SELECT YeniFaturaNo, Durum, COUNT(*) AS Adet
FROM #aday
GROUP BY YeniFaturaNo, Durum
ORDER BY YeniFaturaNo, Durum;

IF @Uygula = 1
BEGIN
    BEGIN TRANSACTION;

    INSERT INTO dbo.sevk_bilgileri (TeklifId)
    SELECT a.TeklifId FROM #aday a
    WHERE NOT EXISTS (SELECT 1 FROM dbo.sevk_bilgileri sb WHERE sb.TeklifId = a.TeklifId);

    UPDATE sb
    SET FaturaNo = a.YeniFaturaNo,
        FaturaTarihi = NULL,
        FaturaGuncelleyenId = NULL,
        FaturaGuncellemeTarihi = SYSDATETIME()
    FROM dbo.sevk_bilgileri sb
    INNER JOIN #aday a ON a.TeklifId = sb.TeklifId;

    PRINT CONCAT(N'Faturalandı işaretlenen teklif: ', @@ROWCOUNT);
    COMMIT TRANSACTION;
END
ELSE
    PRINT N'Önizleme: veri değişmedi. Uygulamak için @Uygula = 1 yapın.';

DROP TABLE #aday;
GO
