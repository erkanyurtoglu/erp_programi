-- ============================================================================
-- 20_satinalma_talep_teklif_siparis.sql
--
-- Satinalma modulunu kurumsal satinalma akisina tasir:
--
--   TALEP  ->  TEKLIF KARSILASTIRMA  ->  SIPARIS(LER)  ->  TESLIM  ->  FATURA
--
-- Neden: ilk surumde her sey tek bir "siparis" formundaydi. Bu yuzden
--   * alinan teklifler hangi kaleme ait belli degildi (5 kalemlik siparise
--     "A firmasi 12.000 TL" yazmak hicbir seyi karsilastirmiyordu),
--   * farkli firmalardan alinan kalemler ayni siparise yaziliyordu; her
--     firmanin kargosu, teslim tarihi ve faturasi ayri oldugu halde,
--   * kargo ile gelmeyen siparislerde de kargo alanlari duruyordu.
--
-- Yeni duzen:
--   dbo.satinalma_talepleri         -- "ne lazim": mudurun talep listesi
--   dbo.satinalma_talep_kalemleri   -- kalem + NE ICIN (hangi cihaz) + miktar
--   dbo.satinalma_teklif_firmalari  -- talebe teklif veren firmalar (sutunlar)
--   dbo.satinalma_teklif_fiyatlari  -- firma x kalem birim fiyati (hucreler)
--   dbo.satinalmalar                -- SIPARIS: firma basina bir tane (SA-0001)
--
-- Birimlerde PC olmadigi icin talebi isteyen kisi degil satinalma muduru
-- girer; IsteyenBirim / IsteyenKisi / IhtiyacTarihi talebin basligindadir.
--
-- Bu betik defalarca calistirilabilir (idempotent), hicbir kaydi silmez
-- (yalnizca bos ve kullanilmayan dbo.satinalma_teklifleri tablosunu kaldirir).
-- Onkosul: db/17_satinalma_ve_cihaz_maliyetleri.sql
-- ============================================================================
USE LiyaErpVeriTabani;
GO

-- SSMS ile ayni oturum ayarlari (sqlcmd varsayilan olarak QUOTED_IDENTIFIER
-- OFF ile calisir).
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'Durum')
BEGIN
    RAISERROR(N'Once 17_satinalma_ve_cihaz_maliyetleri.sql calistirilmali.', 16, 1);
    SET NOEXEC ON;
END
GO

-- ----------------------------------------------------------------------------
-- 1) Talep
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.satinalma_talepleri', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.satinalma_talepleri (
        TalepId          INT IDENTITY(1,1) PRIMARY KEY,
        TalepNo          INT NOT NULL,
        TalepTarihi      DATE NOT NULL CONSTRAINT DF_satinalma_talepleri_Tarih
                             DEFAULT CAST(SYSDATETIME() AS DATE),
        IsteyenBirim     NVARCHAR(50)   NULL,   -- 'Montaj','Elektrik','Üretim','Yazılım','Diğer'
        IsteyenKisi      NVARCHAR(150)  NULL,
        IhtiyacTarihi    DATE           NULL,   -- "ne zaman lazim"
        Aciklama         NVARCHAR(1000) NULL,
        -- Durum saklanmaz, kalemlerin siparise donusup donusmedigine bakilarak
        -- HESAPLANIR (Teklif Toplanıyor / Kısmen Siparişte / Siparişe Dönüştü).
        -- Elle verilen tek durum iptaldir.
        IptalMi          BIT NOT NULL CONSTRAINT DF_satinalma_talepleri_Iptal DEFAULT 0,
        IptalSebebi      NVARCHAR(500)  NULL,
        KullaniciId      INT NULL REFERENCES dbo.kullanicilar(KullaniciId),
        EklenmeTarihi    DATETIME2 NOT NULL CONSTRAINT DF_satinalma_talepleri_Eklenme DEFAULT SYSDATETIME(),
        GuncellemeTarihi DATETIME2 NOT NULL CONSTRAINT DF_satinalma_talepleri_Guncelleme DEFAULT SYSDATETIME()
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_satinalma_talepleri_TalepNo ON dbo.satinalma_talepleri (TalepNo);
END
GO

IF OBJECT_ID('dbo.satinalma_talep_kalemleri', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.satinalma_talep_kalemleri (
        TalepKalemId INT IDENTITY(1,1) PRIMARY KEY,
        TalepId      INT NOT NULL
            CONSTRAINT FK_satinalma_talep_kalemleri_Talep
            REFERENCES dbo.satinalma_talepleri(TalepId) ON DELETE CASCADE,
        SiraNo       INT NOT NULL CONSTRAINT DF_satinalma_talep_kalemleri_Sira DEFAULT 0,
        KalemAdi     NVARCHAR(300) NOT NULL,
        -- Hangi cihaz / is icin: pres, sliper, tiraslama, atolye sarf...
        -- Bir talebin kalemleri farkli cihazlara gidebildigi icin kalemdedir.
        NeIcin       NVARCHAR(250) NULL,
        Miktar       DECIMAL(18,3) NOT NULL,
        Birim        NVARCHAR(20)  NULL,
        Aciklama     NVARCHAR(500) NULL
    );
    CREATE NONCLUSTERED INDEX IX_satinalma_talep_kalemleri_TalepId
        ON dbo.satinalma_talep_kalemleri (TalepId, SiraNo);
    CREATE NONCLUSTERED INDEX IX_satinalma_talep_kalemleri_NeIcin
        ON dbo.satinalma_talep_kalemleri (NeIcin);
END
GO

-- ----------------------------------------------------------------------------
-- 2) Teklifler: firma (sutun) x kalem (satir) = birim fiyat (hucre)
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.satinalma_teklif_firmalari', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.satinalma_teklif_firmalari (
        TeklifFirmaId   INT IDENTITY(1,1) PRIMARY KEY,
        TalepId         INT NOT NULL
            CONSTRAINT FK_satinalma_teklif_firmalari_Talep
            REFERENCES dbo.satinalma_talepleri(TalepId) ON DELETE CASCADE,
        SiraNo          INT NOT NULL CONSTRAINT DF_satinalma_teklif_firmalari_Sira DEFAULT 0,
        -- Kart yoksa (tek seferlik site, yeni firma) ad yine METIN olarak durur.
        TedarikciId     INT NULL
            CONSTRAINT FK_satinalma_teklif_firmalari_Tedarikci
            REFERENCES dbo.tedarikciler(TedarikciId),
        FirmaAdi        NVARCHAR(250) NOT NULL,
        Kaynak          NVARCHAR(20)  NOT NULL CONSTRAINT DF_satinalma_teklif_firmalari_Kaynak
                            DEFAULT N'Tedarikçi',              -- 'Tedarikçi' | 'İnternet'
        TeklifLinki     NVARCHAR(1000) NULL,                   -- internet alimlarinda zorunlu
        -- Bir firma teklifini tek para biriminde verir; kur firma bazindadir
        -- ve teklifin girildigi gunun kuruyla saklanir.
        ParaBirimi      NVARCHAR(5)   NOT NULL CONSTRAINT DF_satinalma_teklif_firmalari_PB DEFAULT N'TL',
        Kur             DECIMAL(18,4) NOT NULL CONSTRAINT DF_satinalma_teklif_firmalari_Kur DEFAULT 1,
        TeslimSuresiGun INT           NULL,
        Notu            NVARCHAR(500) NULL
    );
    CREATE NONCLUSTERED INDEX IX_satinalma_teklif_firmalari_TalepId
        ON dbo.satinalma_teklif_firmalari (TalepId, SiraNo);
END
GO

IF OBJECT_ID('dbo.satinalma_teklif_fiyatlari', 'U') IS NULL
BEGIN
    -- Hucre yoksa firma o kalem icin fiyat vermemistir.
    -- TalepKalemId'de CASCADE yok: SQL Server ayni tablodan (talep) iki ayri
    -- cascade yoluna izin vermez; kalem silinirken fiyatlari program siler.
    CREATE TABLE dbo.satinalma_teklif_fiyatlari (
        TeklifFirmaId INT NOT NULL
            CONSTRAINT FK_satinalma_teklif_fiyatlari_Firma
            REFERENCES dbo.satinalma_teklif_firmalari(TeklifFirmaId) ON DELETE CASCADE,
        TalepKalemId  INT NOT NULL
            CONSTRAINT FK_satinalma_teklif_fiyatlari_Kalem
            REFERENCES dbo.satinalma_talep_kalemleri(TalepKalemId),
        BirimFiyat    DECIMAL(18,4) NOT NULL,
        -- Bu kalem bu firmadan alinacak (kalem basina en fazla bir hucre).
        SecildiMi     BIT NOT NULL CONSTRAINT DF_satinalma_teklif_fiyatlari_Secildi DEFAULT 0,
        CONSTRAINT PK_satinalma_teklif_fiyatlari PRIMARY KEY (TeklifFirmaId, TalepKalemId)
    );
    CREATE NONCLUSTERED INDEX IX_satinalma_teklif_fiyatlari_TalepKalemId
        ON dbo.satinalma_teklif_fiyatlari (TalepKalemId);
END
GO

-- ----------------------------------------------------------------------------
-- 3) Siparis (dbo.satinalmalar): firma basina bir siparis
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'SiparisNo')
BEGIN
    ALTER TABLE dbo.satinalmalar ADD SiparisNo INT NULL;
END
GO

-- Eski kayitlara da numara verilir (giris sirasina gore).
UPDATE s SET SiparisNo = x.Sira
FROM dbo.satinalmalar s
JOIN (
    SELECT SatinalmaId,
           ISNULL((SELECT MAX(SiparisNo) FROM dbo.satinalmalar), 0)
           + ROW_NUMBER() OVER (ORDER BY SatinalmaId) AS Sira
    FROM dbo.satinalmalar WHERE SiparisNo IS NULL
) x ON x.SatinalmaId = s.SatinalmaId;
GO

-- Butun kayitlar numaralandigi icin sutun zorunlu yapilir. (Filtreli
-- "WHERE SiparisNo IS NOT NULL" indeks bilerek kullanilmadi: filtreli
-- indeks, tabloya yazan HER baglantida QUOTED_IDENTIFIER ON ister; bu ayar
-- kapali calisan bir arac/betik siparise hic yazamaz hale gelirdi.)
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar')
           AND name = 'SiparisNo' AND is_nullable = 1)
BEGIN
    ALTER TABLE dbo.satinalmalar ALTER COLUMN SiparisNo INT NOT NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_satinalmalar_SiparisNo'
               AND object_id = OBJECT_ID(N'dbo.satinalmalar'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_satinalmalar_SiparisNo
        ON dbo.satinalmalar (SiparisNo);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'TalepId')
BEGIN
    -- Siparisin dayandigi talep (eski, talepsiz siparislerde NULL).
    ALTER TABLE dbo.satinalmalar ADD TalepId INT NULL
        CONSTRAINT FK_satinalmalar_Talep REFERENCES dbo.satinalma_talepleri(TalepId);
    ALTER TABLE dbo.satinalmalar ADD TeklifFirmaId INT NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'TeslimatSekli')
BEGIN
    -- 'Kargo' | 'Ambar / Nakliye' | 'Tedarikçi getirecek' | 'Biz alacağız'
    -- Kargo firmasi / takip no yalnizca ilk ikisinde anlamlidir.
    ALTER TABLE dbo.satinalmalar ADD TeslimatSekli NVARCHAR(30) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'FaturaTutariTL')
BEGIN
    -- Siparis tutariyla karsilastirilir: fazla faturalandirma burada yakalanir.
    ALTER TABLE dbo.satinalmalar ADD FaturaTutariTL DECIMAL(18,2) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'TekTeklifGerekcesi')
BEGIN
    -- Onay esigini asan siparis tek teklifle verildiyse nedeni.
    ALTER TABLE dbo.satinalmalar ADD TekTeklifGerekcesi NVARCHAR(500) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalma_kalemleri') AND name = 'TalepKalemId')
BEGIN
    ALTER TABLE dbo.satinalma_kalemleri ADD TalepKalemId INT NULL
        CONSTRAINT FK_satinalma_kalemleri_TalepKalem
        REFERENCES dbo.satinalma_talep_kalemleri(TalepKalemId);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalma_kalemleri') AND name = 'NeIcin')
BEGIN
    ALTER TABLE dbo.satinalma_kalemleri ADD NeIcin NVARCHAR(250) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_satinalma_kalemleri_TalepKalemId'
               AND object_id = OBJECT_ID(N'dbo.satinalma_kalemleri'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_satinalma_kalemleri_TalepKalemId
        ON dbo.satinalma_kalemleri (TalepKalemId);
END
GO

-- ----------------------------------------------------------------------------
-- 4) Terk edilen ilk tasarimin teklif tablosu (siparise bagli, kaleme bagli
--    degildi). Bossa kaldirilir; veri varsa dokunulmaz.
-- ----------------------------------------------------------------------------
-- Dinamik SQL: tablo yoksa sorgu derlenirken "gecersiz nesne" hatasi verir.
IF OBJECT_ID('dbo.satinalma_teklifleri', 'U') IS NOT NULL
BEGIN
    EXEC(N'IF NOT EXISTS (SELECT 1 FROM dbo.satinalma_teklifleri) DROP TABLE dbo.satinalma_teklifleri;');
END
GO

SET NOEXEC OFF;
GO
PRINT N'Satinalma talep / teklif / siparis semasi hazir.';
GO
