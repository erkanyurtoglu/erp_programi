-- ============================================================================
-- 18_kalem_bazinda_kargo.sql
--
-- Bir siparisin butun kalemleri ayni kargoyla gelmiyor: 3 kalemlik bir siparis
-- 3 ayri saticidan alinmis, 3 ayri kargoyla yola cikmis olabilir. 17 numarali
-- betikte kargo bilgisi yalnizca SIPARIS BASLIGINDA (dbo.satinalmalar) duruyor;
-- bu durumda ikinci ve ucuncu kargo hic kayda gecmiyor, "hangi parca nerede?"
-- sorusu yine telefonla cozuluyor.
--
-- Cozum: kargo bilgisi KALEM bazina iniyor. Basliktaki KargoFirmasi/KargoTakipNo
-- SILINMIYOR -- tek kargoyla gelen siparislerde (cogunluk) baslik bilgisi hem
-- yeterli hem de kisa yoldur. Kalemdeki alan bos ise basliktaki gecerlidir.
--
-- Bu betik defalarca calistirilabilir (idempotent).
-- Onkosul: db/17_satinalma_ve_cihaz_maliyetleri.sql
-- ============================================================================

IF OBJECT_ID('dbo.satinalma_kalemleri', 'U') IS NULL
BEGIN
    RAISERROR(N'dbo.satinalma_kalemleri yok. Once 17_satinalma_ve_cihaz_maliyetleri.sql calistirilmali.', 16, 1);
    RETURN;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.satinalma_kalemleri') AND name = 'KargoFirmasi'
)
BEGIN
    -- Basliktaki sutunlarla ayni uzunlukta tutuluyor (dbo.satinalmalar).
    ALTER TABLE dbo.satinalma_kalemleri ADD KargoFirmasi NVARCHAR(100) NULL;
    ALTER TABLE dbo.satinalma_kalemleri ADD KargoTakipNo NVARCHAR(100) NULL;
END
GO
