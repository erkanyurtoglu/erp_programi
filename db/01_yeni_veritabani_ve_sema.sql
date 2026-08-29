-- ============================================================================
-- 01_yeni_veritabani_ve_sema.sql
--
-- ONEMLI: Bu script'i calistirmadan ONCE LiyaTeklifVeriTabani'nin TAM YEDEGINI
-- (.bak) alin (SSMS -> veritabani -> sag tik -> Tasks -> Back Up...).
-- Bu script MEVCUT LiyaTeklifVeriTabani'ne HICBIR SEKILDE dokunmuyor;
-- sadece yepyeni ve bos bir "LiyaErpVeriTabani" veritabani ve semasini olusturuyor.
-- ============================================================================

CREATE DATABASE LiyaErpVeriTabani;
GO

USE LiyaErpVeriTabani;
GO

-- ============================================================================
-- FAZ 0: KULLANICI / ROL / YETKI (coklu rol destekli)
-- ============================================================================

CREATE TABLE dbo.kullanicilar (
    KullaniciId    INT IDENTITY(1,1) PRIMARY KEY,
    AdSoyad        NVARCHAR(100) NOT NULL,
    KullaniciAdi   NVARCHAR(50)  NOT NULL UNIQUE,
    SifreHash      NVARCHAR(255) NOT NULL,
    Telefon        NVARCHAR(50)  NULL,
    Pozisyon       NVARCHAR(50)  NULL,
    AktifMi        BIT NOT NULL DEFAULT 1,
    EklenmeTarihi  DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE dbo.roller (
    RolId   INT IDENTITY(1,1) PRIMARY KEY,
    RolAdi  NVARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE dbo.moduller (
    ModulId    INT IDENTITY(1,1) PRIMARY KEY,
    ModulKodu  NVARCHAR(30) NOT NULL UNIQUE,   -- 'SATIS','SATINALMA','STOK','MUHASEBE','YONETIM'
    ModulAdi   NVARCHAR(50) NOT NULL
);

CREATE TABLE dbo.rol_yetkileri (
    RolId           INT NOT NULL REFERENCES dbo.roller(RolId)   ON DELETE CASCADE,
    ModulId         INT NOT NULL REFERENCES dbo.moduller(ModulId) ON DELETE CASCADE,
    Gorebilir       BIT NOT NULL DEFAULT 0,
    Duzenleyebilir  BIT NOT NULL DEFAULT 0,
    PRIMARY KEY (RolId, ModulId)
);

CREATE TABLE dbo.kullanici_rolleri (
    KullaniciId  INT NOT NULL REFERENCES dbo.kullanicilar(KullaniciId) ON DELETE CASCADE,
    RolId        INT NOT NULL REFERENCES dbo.roller(RolId)             ON DELETE CASCADE,
    PRIMARY KEY (KullaniciId, RolId)
);

INSERT INTO dbo.moduller (ModulKodu, ModulAdi) VALUES
    (N'SATIS',      N'Satış'),
    (N'SATINALMA',  N'Satınalma'),
    (N'STOK',       N'Stok'),
    (N'MUHASEBE',   N'Muhasebe'),
    (N'YONETIM',    N'Yönetim');

INSERT INTO dbo.roller (RolAdi) VALUES
    (N'Yönetici'),
    (N'Satış Personeli'),
    (N'Satınalmacı'),
    (N'Stok Sorumlusu'),
    -- Gecis sirasinda eski personelin gecici olarak tam yetkiyle calismaya devam
    -- edebilmesi icin; gocten sonra her kisiye dogru rolu elle atayip bu rolu
    -- kaldiracaksin.
    (N'Göç - Geçici Tam Yetkili');

-- Yonetici: her modulde tam yetki
INSERT INTO dbo.rol_yetkileri (RolId, ModulId, Gorebilir, Duzenleyebilir)
SELECT r.RolId, m.ModulId, 1, 1
FROM dbo.roller r CROSS JOIN dbo.moduller m
WHERE r.RolAdi = N'Yönetici';

-- Gecis rolu: her modulde tam yetki (gecici)
INSERT INTO dbo.rol_yetkileri (RolId, ModulId, Gorebilir, Duzenleyebilir)
SELECT r.RolId, m.ModulId, 1, 1
FROM dbo.roller r CROSS JOIN dbo.moduller m
WHERE r.RolAdi = N'Göç - Geçici Tam Yetkili';

-- Satis Personeli: sadece Satis
INSERT INTO dbo.rol_yetkileri (RolId, ModulId, Gorebilir, Duzenleyebilir)
SELECT r.RolId, m.ModulId, 1, 1
FROM dbo.roller r CROSS JOIN dbo.moduller m
WHERE r.RolAdi = N'Satış Personeli' AND m.ModulKodu = N'SATIS';

-- Satinalmaci: sadece Satinalma
INSERT INTO dbo.rol_yetkileri (RolId, ModulId, Gorebilir, Duzenleyebilir)
SELECT r.RolId, m.ModulId, 1, 1
FROM dbo.roller r CROSS JOIN dbo.moduller m
WHERE r.RolAdi = N'Satınalmacı' AND m.ModulKodu = N'SATINALMA';

-- Stok Sorumlusu: sadece Stok
INSERT INTO dbo.rol_yetkileri (RolId, ModulId, Gorebilir, Duzenleyebilir)
SELECT r.RolId, m.ModulId, 1, 1
FROM dbo.roller r CROSS JOIN dbo.moduller m
WHERE r.RolAdi = N'Stok Sorumlusu' AND m.ModulKodu = N'STOK';

-- ============================================================================
-- FAZ 1: SATIS / TEKLIF
-- ============================================================================

CREATE TABLE dbo.musteriler (
    MusteriId           INT IDENTITY(1,1) PRIMARY KEY,
    FirmaAdi             NVARCHAR(250) NOT NULL,
    FirmaAdresi          NVARCHAR(500) NULL,
    FirmaTelefonu        NVARCHAR(50)  NULL,
    FirmaEposta          NVARCHAR(100) NULL,
    VergiDairesi         NVARCHAR(100) NULL,
    VergiNumarasi        NVARCHAR(50)  NULL,
    IlgiliKisi           NVARCHAR(150) NULL,
    IlgiliKisiTelefonu   NVARCHAR(50)  NULL,
    EklenmeTarihi        DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE dbo.urunler (
    UrunId            INT IDENTITY(1,1) PRIMARY KEY,
    UrunKodu          NVARCHAR(50)  NULL,
    Kategori          NVARCHAR(100) NULL,
    UrunAciklamasi    NVARCHAR(MAX) NULL,
    UrunAciklamasiEn  NVARCHAR(MAX) NULL,
    BirimFiyat        DECIMAL(18,2) NULL,
    ParaBirimi        NVARCHAR(5) NOT NULL DEFAULT 'TL',
    GuncelMaliyetTL   DECIMAL(18,2) NULL,   -- Faz 3'te son satinalmadan otomatik guncellenecek
    EklenmeTarihi     DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE dbo.teklifler (
    TeklifId              INT IDENTITY(1,1) PRIMARY KEY,
    MusteriId             INT NOT NULL REFERENCES dbo.musteriler(MusteriId),
    KullaniciId           INT NULL REFERENCES dbo.kullanicilar(KullaniciId),
    OlusturmaTarihi       DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    GenelIndirimOrani     DECIMAL(5,2) NOT NULL DEFAULT 0,
    KdvOrani              DECIMAL(5,2) NOT NULL DEFAULT 0,
    Durum                 NVARCHAR(50) NOT NULL DEFAULT N'Beklemede',
    MusteriNotu           NVARCHAR(1000) NULL,
    ParaBirimi            NVARCHAR(5) NOT NULL DEFAULT 'TL',
    Dil                   NVARCHAR(5) NOT NULL DEFAULT N'TR',
    SatisSozlesmesiMetni  NVARCHAR(MAX) NULL,
    IlgiliKisi            NVARCHAR(100) NULL,
    IlgiliKisiTelefonu    NVARCHAR(100) NULL,
    IlgiliKisiEposta      NVARCHAR(100) NULL,
    TeslimatSekli         NVARCHAR(200) NULL,
    TeslimatYeri          NVARCHAR(200) NULL,
    TeslimatTarihi        DATETIME2 NULL,
    TeslimTarihi          DATETIME2 NULL,
    KabulTarihi           DATETIME2 NULL,
    UretimPdfTarihi       DATETIME2 NULL
);
CREATE INDEX IX_teklifler_OlusturmaTarihi ON dbo.teklifler(OlusturmaTarihi DESC);
CREATE INDEX IX_teklifler_Durum_OlusturmaTarihi ON dbo.teklifler(Durum, OlusturmaTarihi DESC);

CREATE TABLE dbo.teklif_kalemleri (
    TeklifKalemId        INT IDENTITY(1,1) PRIMARY KEY,
    TeklifId             INT NOT NULL REFERENCES dbo.teklifler(TeklifId) ON DELETE CASCADE,
    UrunId               INT NOT NULL REFERENCES dbo.urunler(UrunId),
    Adet                 INT NOT NULL,
    BirimFiyat           DECIMAL(18,2) NOT NULL,
    IndirimliBirimFiyat  DECIMAL(18,2) NOT NULL,
    ToplamTutar          DECIMAL(18,2) NOT NULL,
    MaliyetFiyati        DECIMAL(18,2) NULL,
    UrunAciklamasi       NVARCHAR(MAX) NULL,
    UrunAciklamasiTr     NVARCHAR(MAX) NULL,
    UrunAciklamasiEn     NVARCHAR(MAX) NULL,
    ParaBirimi           NVARCHAR(5) NOT NULL DEFAULT 'TL',
    Kur                  DECIMAL(18,4) NOT NULL DEFAULT 1,
    -- Eski sistemden korunan, anlami tam netlesmemis tarihsel alanlar (veri kaybi olmasin diye tasindi):
    EskiFiyatTL          DECIMAL(18,2) NULL,
    EskiFiyatUSD         DECIMAL(18,2) NULL,
    EskiFiyatEUR         DECIMAL(18,2) NULL,
    Tamamlandi           BIT NOT NULL DEFAULT 0,
    UretimNotu           NVARCHAR(1000) NULL
);

CREATE TABLE dbo.teklif_toplamlari (
    TeklifId         INT PRIMARY KEY REFERENCES dbo.teklifler(TeklifId) ON DELETE CASCADE,
    IndirimliToplam  DECIMAL(18,2) NOT NULL DEFAULT 0,
    KdvTutari        DECIMAL(18,2) NOT NULL DEFAULT 0,
    GenelToplam      DECIMAL(18,2) NOT NULL DEFAULT 0,
    PaketlemeUcreti  DECIMAL(18,2) NOT NULL DEFAULT 0,
    TasimaUcreti     DECIMAL(18,2) NOT NULL DEFAULT 0
);

-- ONEMLI: TeklifId burada UNIQUE -> bir teklifin birden fazla sevk kaydina sahip
-- olmasi fiziksel olarak imkansiz hale geliyor (eski semadeki spagetti/fan-out
-- sorununun kokten cozumu).
CREATE TABLE dbo.sevk_bilgileri (
    SevkBilgileriId       INT IDENTITY(1,1) PRIMARY KEY,
    TeklifId              INT NOT NULL UNIQUE REFERENCES dbo.teklifler(TeklifId) ON DELETE CASCADE,
    FaturaBasligi         NVARCHAR(200) NULL,
    FaturaAdresi          NVARCHAR(500) NULL,
    FaturaVergiDairesi    NVARCHAR(150) NULL,
    FaturaVergiNo         NVARCHAR(50)  NULL,
    FaturaYetkili         NVARCHAR(150) NULL,
    FaturaTelefon         NVARCHAR(50)  NULL,
    FaturaFax             NVARCHAR(50)  NULL,
    FaturaEposta          NVARCHAR(150) NULL,
    IrsaliyeBasligi       NVARCHAR(200) NULL,
    IrsaliyeAdresi        NVARCHAR(500) NULL,
    IrsaliyeVergiDairesi  NVARCHAR(150) NULL,
    IrsaliyeVergiNo       NVARCHAR(50)  NULL,
    IrsaliyeYetkili       NVARCHAR(150) NULL,
    IrsaliyeTelefon       NVARCHAR(50)  NULL,
    IrsaliyeEposta        NVARCHAR(150) NULL,
    SiparisKdv            NVARCHAR(50)  NULL,
    FaturaSekli           NVARCHAR(150) NULL,
    Garanti               NVARCHAR(200) NULL,
    Teslimat              NVARCHAR(200) NULL,
    Odeme                 NVARCHAR(200) NULL,
    Nakliye               NVARCHAR(200) NULL,
    Kalibrasyon           NVARCHAR(200) NULL,
    Egitim                NVARCHAR(200) NULL,
    ReferansNumarasi      NVARCHAR(200) NULL,
    EkFaturaNotu          NVARCHAR(500) NULL,
    Aciklamalar           NVARCHAR(MAX) NULL,
    SiparisTarihi         DATE NULL
);

-- ============================================================================
-- FAZ 3 (SATINALMA) - simdiden hazir, veri gocu YOK (eski sistemde gercek
-- satinalma gecmisi tutulmuyordu, bkz. urun_maliyetleri tablosu). Bu tablolar
-- bostur, Faz 3'te program uzerinden doldurulmaya baslanacak.
-- ============================================================================

CREATE TABLE dbo.tedarikciler (
    TedarikciId    INT IDENTITY(1,1) PRIMARY KEY,
    FirmaAdi       NVARCHAR(250) NOT NULL,
    Adres          NVARCHAR(500) NULL,
    Telefon        NVARCHAR(50)  NULL,
    Eposta         NVARCHAR(100) NULL,
    VergiDairesi   NVARCHAR(100) NULL,
    VergiNumarasi  NVARCHAR(50)  NULL,
    IlgiliKisi     NVARCHAR(150) NULL,
    EklenmeTarihi  DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE dbo.satinalmalar (
    SatinalmaId      INT IDENTITY(1,1) PRIMARY KEY,
    TedarikciId      INT NOT NULL REFERENCES dbo.tedarikciler(TedarikciId),
    KullaniciId      INT NULL REFERENCES dbo.kullanicilar(KullaniciId),
    SatinalmaTarihi  DATE NOT NULL DEFAULT CAST(SYSDATETIME() AS DATE),
    Aciklama         NVARCHAR(500) NULL
);

CREATE TABLE dbo.satinalma_kalemleri (
    SatinalmaKalemId  INT IDENTITY(1,1) PRIMARY KEY,
    SatinalmaId       INT NOT NULL REFERENCES dbo.satinalmalar(SatinalmaId) ON DELETE CASCADE,
    UrunId            INT NOT NULL REFERENCES dbo.urunler(UrunId),
    Adet              INT NOT NULL,
    BirimFiyatDoviz   DECIMAL(18,4) NOT NULL,
    ParaBirimi        NVARCHAR(5) NOT NULL DEFAULT 'TL',   -- 'TL','USD','EUR'
    Kur               DECIMAL(18,4) NOT NULL DEFAULT 1,    -- kayit aninda TCMB'den donmus kur
    BirimFiyatTL      DECIMAL(18,2) NOT NULL,              -- BirimFiyatDoviz * Kur
    ToplamTutarTL     DECIMAL(18,2) NOT NULL,
    UrunLinki         NVARCHAR(500) NULL                   -- urunun alindigi web sayfasi (opsiyonel)
);

PRINT N'LiyaErpVeriTabani semasi olusturuldu.';
