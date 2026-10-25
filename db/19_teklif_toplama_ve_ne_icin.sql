-- ============================================================================
-- 19_teklif_toplama_ve_ne_icin.sql
--
-- Iki eksigi kapatir:
--
-- 1) "Bu mal hangi cihaz icin alindi?" -- pres mi, sliper mi, tiraslama mi?
--    Bu bilgi bugune kadar yalnizca akilda tutuluyordu. Bir siparisin
--    kalemleri FARKLI cihazlara gidebildigi icin (10 kalemin 3'u bir cihaz,
--    4'u digeri) alan siparis basliginda degil KALEM bazindadir.
--
-- 2) Teklif toplama izi -- "3 yerden fiyat alindi mi?" Patron onayi esigi
--    vardi ama onayin dayandigi karsilastirma kayda gecmiyordu. Artik
--    siparise alinan teklifler yazilir ve hangisinin kabul edildigi
--    isaretlenir. Esigi asan siparislerde en az iki teklif istenir; tek
--    teklifle alindiysa GEREKCESI yazilir (tek kaynak gerekcesi:
--    "baska yerde yok", "acil", "anlasmali tedarikci"...).
--
-- NOT: Buradaki dbo.satinalma_teklifleri tablosu (siparise bagli, kaleme
-- bagli olmayan teklif listesi) 20_satinalma_talep_teklif_siparis.sql ile
-- terk edildi; teklifler artik kalem x firma tablosunda tutulur. 20 numarali
-- betik bu tabloyu bossa kaldirir.
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

-- ----------------------------------------------------------------------------
-- 1) Kalem bazinda "ne icin alindi"
-- ----------------------------------------------------------------------------

-- Serbest metindir: cihaz kartlari (dbo.cihazlar) henuz ekrandan girilmiyor
-- ve alimlar her zaman bir cihaza da gitmiyor (atolye sarf, bakim, numune).
-- Yazim dagilmasin diye ekran, daha once yazilmis adlari oneri olarak dusurur
-- -- kalem adlarinda kullanilan desenin aynisi.
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.satinalma_kalemleri') AND name = 'NeIcin'
)
BEGIN
    ALTER TABLE dbo.satinalma_kalemleri ADD NeIcin NVARCHAR(250) NULL;
END
GO

-- Oneri sorgusu bu sutun uzerinden DISTINCT cekiyor.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_satinalma_kalemleri_NeIcin'
      AND object_id = OBJECT_ID(N'dbo.satinalma_kalemleri')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_satinalma_kalemleri_NeIcin
        ON dbo.satinalma_kalemleri (NeIcin);
END
GO

-- ----------------------------------------------------------------------------
-- 2) Tek teklifle alim gerekcesi (siparis basliginda)
-- ----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'TekTeklifGerekcesi'
)
BEGIN
    ALTER TABLE dbo.satinalmalar ADD TekTeklifGerekcesi NVARCHAR(500) NULL;
END
GO

-- ----------------------------------------------------------------------------
-- 3) dbo.satinalma_teklifleri : siparis icin alinan fiyat teklifleri
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.satinalma_teklifleri', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.satinalma_teklifleri (
        SatinalmaTeklifId INT IDENTITY(1,1) PRIMARY KEY,
        SatinalmaId     INT NOT NULL
            CONSTRAINT FK_satinalma_teklifleri_Satinalma
            REFERENCES dbo.satinalmalar(SatinalmaId) ON DELETE CASCADE,
        -- Teklif veren firmanin karti olmayabilir (tek seferlik site, yeni
        -- firma): ad her zaman METIN olarak saklanir, kart varsa TedarikciId
        -- de doldurulur.
        TedarikciId     INT NULL
            CONSTRAINT FK_satinalma_teklifleri_Tedarikci
            REFERENCES dbo.tedarikciler(TedarikciId),
        FirmaAdi        NVARCHAR(250) NOT NULL,
        -- Teklif KENDI para biriminde saklanir; TutarTL o gunku kurla
        -- hesaplanip DONDURULUR ki karsilastirma sonradan kur degisince
        -- bozulmasin (cihaz recetesindeki ayni gerekce).
        TeklifTutari    DECIMAL(18,4) NOT NULL CONSTRAINT DF_satinalma_teklifleri_Tutar DEFAULT 0,
        ParaBirimi      NVARCHAR(5)   NOT NULL CONSTRAINT DF_satinalma_teklifleri_PB   DEFAULT N'TL',
        Kur             DECIMAL(18,4) NOT NULL CONSTRAINT DF_satinalma_teklifleri_Kur  DEFAULT 1,
        TutarTL         DECIMAL(18,2) NOT NULL CONSTRAINT DF_satinalma_teklifleri_TutarTL DEFAULT 0,
        TeslimSuresiGun INT           NULL,   -- "15 gun sonra teslim"
        Notu            NVARCHAR(500) NULL,
        -- Kabul edilen teklif. En ucuz her zaman secilmez (teslim suresi,
        -- kalite, vade); hangisinin NEDEN secildigi Notu'na yazilir.
        SecilenMi       BIT NOT NULL CONSTRAINT DF_satinalma_teklifleri_Secilen DEFAULT 0,
        EklenmeTarihi   DATETIME2 NOT NULL
            CONSTRAINT DF_satinalma_teklifleri_Eklenme DEFAULT SYSDATETIME()
    );

    CREATE NONCLUSTERED INDEX IX_satinalma_teklifleri_SatinalmaId
        ON dbo.satinalma_teklifleri (SatinalmaId);
END
GO
