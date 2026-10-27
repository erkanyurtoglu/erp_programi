-- ============================================================================
-- 25_teklif_gecerlilik_gunu.sql
--
-- dbo.teklifler'e GecerlilikGunu eklenir: sozlesmedeki {{GECERLILIK_TARIHI}}
-- (teklif tarihi + gun) bu tekliften hesaplanir. Eskiden gun sayisi kodda
-- sabitti (3) ve PDF her basildiginda yeniden hesaplandigi icin sabit
-- degisirse eski tekliflerin geçerlilik tarihi de degisirdi.
--
-- Yeni teklif kaydedilirken Yonetim / Sistem Ayarlari'ndaki
-- TEKLIF_GECERLILIK_GUNU degeri yazilir. Mevcut satirlar NULL kalir ve
-- program onlari eskisi gibi 3 gun sayar -- mevcut veriye DOKUNULMAZ.
--
-- Defalarca calistirilabilir.
-- ============================================================================
USE LiyaErpVeriTabani;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.teklifler') AND name = 'GecerlilikGunu')
BEGIN
    ALTER TABLE dbo.teklifler ADD GecerlilikGunu INT NULL
        CONSTRAINT CK_teklifler_GecerlilikGunu CHECK (GecerlilikGunu BETWEEN 1 AND 365);
END
GO
