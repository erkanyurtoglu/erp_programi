-- ============================================================================
-- 22_stok_muhasebe_modullerini_kaldir.sql
--
-- Stok ve Muhasebe modulleri programda istenmiyor; ana menude "Yakinda"
-- kartlari olarak duruyorlardi.
--
--   * dbo.moduller'den STOK ve MUHASEBE silinir; rol_yetkileri satirlari
--     ON DELETE CASCADE ile gider.
--   * Yalnizca Stok icin acilmis "Stok Sorumlusu" rolu, kimseye atanmamissa
--     silinir (atanmissa kisinin rolu elle degistirilmeli).
--
-- Satinalmadaki fatura alanlari ve MuhasebeyeIletildiMi isareti KALIR.
-- Defalarca calistirilabilir.
-- Onkosul: db/01_yeni_veritabani_ve_sema.sql
-- ============================================================================
USE LiyaErpVeriTabani;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
GO

DELETE FROM dbo.moduller WHERE ModulKodu IN (N'STOK', N'MUHASEBE');
GO

DELETE r
FROM dbo.roller r
WHERE r.RolAdi = N'Stok Sorumlusu'
  AND NOT EXISTS (SELECT 1 FROM dbo.kullanici_rolleri kr WHERE kr.RolId = r.RolId)
  AND NOT EXISTS (SELECT 1 FROM dbo.rol_yetkileri ry WHERE ry.RolId = r.RolId);
GO

IF EXISTS (SELECT 1 FROM dbo.roller WHERE RolAdi = N'Stok Sorumlusu')
    PRINT N'UYARI: "Stok Sorumlusu" rolu kullaniciya atanmis oldugu icin silinmedi.';
GO
PRINT N'Stok ve Muhasebe modulleri kaldirildi.';
