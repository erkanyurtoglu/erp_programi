-- ============================================================================
-- 31_muhasebe_modulu.sql
--
-- ISTEK
-- Muhasebe, Alınan Tekliflerim'deki irsaliye bilgilerini, kalem aciklamalarini,
-- fiyat ve adetleri kopyalayip kendi programinda fatura/irsaliye kesiyordu.
-- Bunun icin ayri bir "Muhasebe" karti: faturalanacak teklifler, tek tikla
-- kopyalanan fatura bilgileri ve kalemler, fatura/irsaliye no girisi.
--
-- Bu bir muhasebe sistemi (cari, tahsilat, vade) DEGILDIR; db/22'de kaldirilan
-- eski MUHASEBE modulunun yeniden acilmasi da degildir -- yalnizca fatura
-- kesmek icin veri aktarim ekranidir. Onkosul: db/30_fatura_takibi.sql.
--
--   * dbo.moduller'e MUHASEBE eklenir.
--   * "Muhasebe" rolu olusturulur (MUHASEBE: gorebilir + duzenleyebilir).
--   * Yonetici rolune MUHASEBE yetkisi verilir.
--   * Pozisyonu "Muhasebe" ile baslayan AKTIF personele Muhasebe rolu atanir
--     (mevcut rolleri korunur). Baskasina vermek icin Personellerim ekranini
--     kullanin.
--
-- Defalarca calistirilabilir.
-- ============================================================================
USE LiyaErpVeriTabani;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.moduller WHERE ModulKodu = N'MUHASEBE')
    INSERT INTO dbo.moduller (ModulKodu, ModulAdi) VALUES (N'MUHASEBE', N'Muhasebe');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.roller WHERE RolAdi = N'Muhasebe')
    INSERT INTO dbo.roller (RolAdi) VALUES (N'Muhasebe');
GO

-- Muhasebe ve Yonetici rolleri: MUHASEBE modulunu gorur ve duzenler.
INSERT INTO dbo.rol_yetkileri (RolId, ModulId, Gorebilir, Duzenleyebilir)
SELECT r.RolId, m.ModulId, 1, 1
FROM dbo.roller r
CROSS JOIN dbo.moduller m
WHERE r.RolAdi IN (N'Muhasebe', N'Yönetici')
  AND m.ModulKodu = N'MUHASEBE'
  AND NOT EXISTS (SELECT 1 FROM dbo.rol_yetkileri ry
                  WHERE ry.RolId = r.RolId AND ry.ModulId = m.ModulId);
GO

INSERT INTO dbo.kullanici_rolleri (KullaniciId, RolId)
SELECT k.KullaniciId, r.RolId
FROM dbo.kullanicilar k
CROSS JOIN dbo.roller r
WHERE r.RolAdi = N'Muhasebe'
  AND k.AktifMi = 1
  AND k.Pozisyon LIKE N'Muhasebe%'
  AND NOT EXISTS (SELECT 1 FROM dbo.kullanici_rolleri kr
                  WHERE kr.KullaniciId = k.KullaniciId AND kr.RolId = r.RolId);
GO

PRINT N'Muhasebe modulu ve rolu eklendi (veya zaten mevcuttu).';
