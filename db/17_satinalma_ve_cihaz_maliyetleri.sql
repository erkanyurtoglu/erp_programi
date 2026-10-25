-- ============================================================================
-- 17 - SATINALMA MODULU + CIHAZ MALIYETLERI
--
-- Bu dosya satinalma modulunun veri temelini kurar. Iki is yapar:
--
-- 1) SIPARIS TAKIBI
--    Bugun satinalma muduru siparisleri DEFTERE yaziyor; urun geldi mi
--    gelmedi mi kargocu soylemezse bilinmiyor, internetten alinan urunun
--    linki kayitli tutulmuyor. Mevcut dbo.satinalmalar /
--    dbo.satinalma_kalemleri tablolari (bkz. 01_yeni_veritabani_ve_sema.sql,
--    FAZ 3) bunun icin fazla cilpak: sadece tedarikci + tarih + kalem var.
--    Buraya durum, teslim takibi, kargo, isteyen birim, patron onayi ve
--    fatura alanlari ekleniyor.
--
-- 2) CIHAZ MALIYETLERI (Excel'in yerine)
--    Satinalma muduru her cihazin parca/iscilik maliyetini Excel'de
--    tutuyordu: her cihaz bir sayfa, satirlar MEKANIK / SULAMA / ELEKTRONIK
--    / GENEL gruplari altinda, her satirda adet - birim fiyat - para birimi
--    - kur - TL karsiligi - firma. Ikinci bir sayfada ise maliyeti degisen
--    urunun eski/yeni maliyeti, kar orani ve yeni satis fiyati ELLE
--    tutuluyordu. Burada:
--       dbo.cihazlar                -> Excel'deki her bir sayfa
--       dbo.cihaz_recete_kalemleri  -> o sayfadaki satirlar
--       dbo.cihaz_maliyet_gecmisi   -> ikinci sayfanin OTOMATIK uretilen hali
--
-- Recete kalemleri BILEREK serbest metindir (UrunId zorunlu degil): her
-- cihazin parcalari kendi icinde belli, ortak parca az. Ayni parcayi
-- satin alirken program daha once ayni adla girilmis kayitlari onerir.
--
-- Bu betik YALNIZCA yeni sutun / tablo / indeks ekler, hicbir kaydi silmez
-- ve mevcut veriyi degistirmez. Tekrar calistirilmasi zararsizdir.
-- ============================================================================
USE LiyaErpVeriTabani;
GO

-- ----------------------------------------------------------------------------
-- 0) Genel ayar tablosu (anahtar/deger)
--    Simdilik tek musterisi "patron onayi esigi", ama ileride baska ayarlar
--    da buraya girsin diye genel tutuldu.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.ayarlar', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ayarlar (
        Anahtar         NVARCHAR(100) NOT NULL PRIMARY KEY,
        Deger           NVARCHAR(500) NULL,
        Aciklama        NVARCHAR(500) NULL,
        GuncellemeTarihi DATETIME2 NOT NULL DEFAULT SYSDATETIME()
    );
END
GO

-- Esigin ustundeki siparisler, "Patron Onayi Bekliyor" durumuna dusen
-- siparislerdir. Patronun programda hesabi yok; mudur sozlu onayi alip
-- kutuyu isaretler, program kimin ne zaman isaretledigini iz olarak tutar.
IF NOT EXISTS (SELECT 1 FROM dbo.ayarlar WHERE Anahtar = N'SATINALMA_PATRON_ONAY_ESIGI_TL')
BEGIN
    INSERT INTO dbo.ayarlar (Anahtar, Deger, Aciklama) VALUES
        (N'SATINALMA_PATRON_ONAY_ESIGI_TL', N'50000',
         N'Bu tutarin (TL) uzerindeki satinalmalar icin patron onayi istenir. 0 = onay hic istenmez.');
END
GO

-- ----------------------------------------------------------------------------
-- 1) dbo.satinalmalar : siparis basligi
-- ----------------------------------------------------------------------------

-- Internetten yapilan alimlarda tedarikci karti olmayabilir (tek seferlik
-- site). Bu yuzden TedarikciId artik zorunlu degil; yerine SiparisKaynagi +
-- SiparisLinki kullanilir. Sutun zaten NULL ise ALTER zararsizdir.
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'TedarikciId' AND is_nullable = 0
)
BEGIN
    ALTER TABLE dbo.satinalmalar ALTER COLUMN TedarikciId INT NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'Durum')
BEGIN
    -- Durum degerleri, teklif tarafiyla ayni yazim kurallarini izler (Turkce
    -- karakterli, bkz. dbo.teklifler.Durum -> 'Beklemede' / 'Tamamlandı'):
    --   'Taslak', 'Patron Onayı Bekliyor', 'Sipariş Verildi', 'Kargoda',
    --   'Kısmi Teslim', 'Teslim Alındı', 'İptal', 'Reddedildi'
    ALTER TABLE dbo.satinalmalar
        ADD Durum NVARCHAR(30) NOT NULL CONSTRAINT DF_satinalmalar_Durum DEFAULT N'Sipariş Verildi';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'SiparisKaynagi')
BEGIN
    -- 'Tedarikçi' | 'İnternet'
    ALTER TABLE dbo.satinalmalar
        ADD SiparisKaynagi NVARCHAR(20) NOT NULL
            CONSTRAINT DF_satinalmalar_SiparisKaynagi DEFAULT N'Tedarikçi';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'SiparisLinki')
BEGIN
    -- Internetten alindiysa siparisin verildigi sayfa/sepet linki. Kalem
    -- bazindaki link icin satinalma_kalemleri.UrunLinki kullanilir.
    ALTER TABLE dbo.satinalmalar ADD SiparisLinki NVARCHAR(1000) NULL;
END
GO

-- Birimlerde PC olmadigi icin ayri bir "talep" ekrani YOK; istegi kimin
-- yaptigini mudur siparise yazar. Ileride birimlere PC gelirse talep ekrani
-- bu alanlarin uzerine kurulabilir.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'IsteyenBirim')
BEGIN
    -- 'Montaj', 'Elektrik', 'Üretim', 'Yazılım', 'Diğer'
    ALTER TABLE dbo.satinalmalar ADD IsteyenBirim NVARCHAR(50)  NULL;
    ALTER TABLE dbo.satinalmalar ADD IsteyenKisi  NVARCHAR(150) NULL;
    ALTER TABLE dbo.satinalmalar ADD IhtiyacTarihi DATE         NULL;  -- "ne zaman lazim"
END
GO

-- Teslim takibi: gecikme uyarisi BeklenenTeslimTarihi ile hesaplanir
-- (bugunu gecmis ve Durum hala 'Teslim Alindi'/'Iptal' degilse geciken).
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'BeklenenTeslimTarihi')
BEGIN
    ALTER TABLE dbo.satinalmalar ADD BeklenenTeslimTarihi DATE NULL;
    ALTER TABLE dbo.satinalmalar ADD TeslimAlmaTarihi     DATE NULL;
    ALTER TABLE dbo.satinalmalar ADD KargoFirmasi  NVARCHAR(100) NULL;
    ALTER TABLE dbo.satinalmalar ADD KargoTakipNo  NVARCHAR(100) NULL;
END
GO

-- Patron onayi. PatronOnayiGerekliMi, siparis kaydedilirken o anki esikle
-- hesaplanip DONDURULUR: esik sonradan degisince eski siparislerin gecmisi
-- bozulmasin.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'PatronOnayiGerekliMi')
BEGIN
    ALTER TABLE dbo.satinalmalar
        ADD PatronOnayiGerekliMi BIT NOT NULL
            CONSTRAINT DF_satinalmalar_PatronOnayiGerekliMi DEFAULT 0;
    ALTER TABLE dbo.satinalmalar
        ADD PatronOnayliMi BIT NOT NULL
            CONSTRAINT DF_satinalmalar_PatronOnayliMi DEFAULT 0;
    ALTER TABLE dbo.satinalmalar ADD PatronOnayTarihi DATETIME2 NULL;
    -- Kutuyu isaretleyen kullanici (patron degil, mudur): sozlu onayin izi.
    ALTER TABLE dbo.satinalmalar
        ADD OnayiIsaretleyenKullaniciId INT NULL
            CONSTRAINT FK_satinalmalar_OnayiIsaretleyen
            REFERENCES dbo.kullanicilar(KullaniciId);
    ALTER TABLE dbo.satinalmalar ADD RedSebebi NVARCHAR(500) NULL;
END
GO

-- Fatura: odeme/mutabakat muhasebenin isi. Satinalmada sadece faturanin
-- bilgisi ve muhasebeye iletilip iletilmedigi durur.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'FaturaNo')
BEGIN
    ALTER TABLE dbo.satinalmalar ADD FaturaNo     NVARCHAR(50) NULL;
    ALTER TABLE dbo.satinalmalar ADD FaturaTarihi DATE         NULL;
    ALTER TABLE dbo.satinalmalar
        ADD MuhasebeyeIletildiMi BIT NOT NULL
            CONSTRAINT DF_satinalmalar_MuhasebeyeIletildiMi DEFAULT 0;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalmalar') AND name = 'GuncellemeTarihi')
BEGIN
    ALTER TABLE dbo.satinalmalar
        ADD GuncellemeTarihi DATETIME2 NOT NULL
            CONSTRAINT DF_satinalmalar_GuncellemeTarihi DEFAULT SYSDATETIME();
END
GO

-- ----------------------------------------------------------------------------
-- 2) dbo.satinalma_kalemleri : siparis satirlari
-- ----------------------------------------------------------------------------

-- Kalem artik serbest metin olabilir: UrunId zorunluluktan cikiyor, yerine
-- KalemAdi geliyor. UrunId dolduruldugunda urun kartiyla bag kurulur
-- (opsiyonel).
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.satinalma_kalemleri') AND name = 'UrunId' AND is_nullable = 0
)
BEGIN
    ALTER TABLE dbo.satinalma_kalemleri ALTER COLUMN UrunId INT NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalma_kalemleri') AND name = 'KalemAdi')
BEGIN
    ALTER TABLE dbo.satinalma_kalemleri ADD KalemAdi NVARCHAR(300) NULL;
    ALTER TABLE dbo.satinalma_kalemleri ADD Birim    NVARCHAR(20)  NULL;  -- adet, kg, metre, saat...
    ALTER TABLE dbo.satinalma_kalemleri ADD Aciklama NVARCHAR(500) NULL;
END
GO

-- Kismi teslim: 10 istenip 6 geldiginde GelenAdet = 6 olur, siparis
-- 'Kismi Teslim' durumunda kalir.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.satinalma_kalemleri') AND name = 'GelenAdet')
BEGIN
    ALTER TABLE dbo.satinalma_kalemleri
        ADD GelenAdet DECIMAL(18,3) NOT NULL
            CONSTRAINT DF_satinalma_kalemleri_GelenAdet DEFAULT 0;
END
GO

-- Adet INT olarak olusturulmustu; Excel'deki maliyet satirlarinda 2,5 kg /
-- 1,5 saat gibi kusuratli miktarlar var. Ayni dert siparis kaleminde de
-- gecerli, ondalikli hale getiriliyor.
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.satinalma_kalemleri')
      AND name = 'Adet'
      AND system_type_id = TYPE_ID('int')
)
BEGIN
    ALTER TABLE dbo.satinalma_kalemleri ALTER COLUMN Adet DECIMAL(18,3) NOT NULL;
END
GO

-- Internetten alinan urunun linki icin UrunLinki sutunu semada zaten var,
-- ancak 500 karakter bazi pazaryeri linkleri icin kisa kaliyor.
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.satinalma_kalemleri')
      AND name = 'UrunLinki' AND max_length = 1000   -- NVARCHAR(500) = 1000 bayt
)
BEGIN
    ALTER TABLE dbo.satinalma_kalemleri ALTER COLUMN UrunLinki NVARCHAR(1000) NULL;
END
GO

-- ----------------------------------------------------------------------------
-- 3) dbo.cihazlar : Excel'deki her bir maliyet sayfasi
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.cihazlar', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.cihazlar (
        CihazId         INT IDENTITY(1,1) PRIMARY KEY,
        CihazAdi        NVARCHAR(250) NOT NULL,
        Aciklama        NVARCHAR(1000) NULL,
        -- Varsayilan kar orani (%). Maliyet degistikce degisebilir; her
        -- maliyet gecmisi satiri o anki orani KENDI icinde sakladigi icin
        -- buradaki degisiklik gecmisi bozmaz.
        KarOrani        DECIMAL(6,2) NOT NULL CONSTRAINT DF_cihazlar_KarOrani DEFAULT 80,
        -- Asagidaki iki alan recete kalemlerinden hesaplanip buraya yazilir
        -- (her kaydetmede guncellenir); liste ekraninin her cihaz icin
        -- receteyi toplamasini onlemek icin.
        ToplamMaliyetTL DECIMAL(18,2) NOT NULL CONSTRAINT DF_cihazlar_ToplamMaliyetTL DEFAULT 0,
        SatisFiyatiTL   DECIMAL(18,2) NOT NULL CONSTRAINT DF_cihazlar_SatisFiyatiTL DEFAULT 0,
        AktifMi         BIT NOT NULL CONSTRAINT DF_cihazlar_AktifMi DEFAULT 1,
        KullaniciId     INT NULL REFERENCES dbo.kullanicilar(KullaniciId),
        EklenmeTarihi   DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
        GuncellemeTarihi DATETIME2 NOT NULL DEFAULT SYSDATETIME()
    );

    CREATE NONCLUSTERED INDEX IX_cihazlar_AktifMi_CihazAdi ON dbo.cihazlar (AktifMi, CihazAdi);
END
GO

-- ----------------------------------------------------------------------------
-- 4) dbo.cihaz_recete_kalemleri : Excel sayfasindaki satirlar
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.cihaz_recete_kalemleri', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.cihaz_recete_kalemleri (
        ReceteKalemId   INT IDENTITY(1,1) PRIMARY KEY,
        CihazId         INT NOT NULL REFERENCES dbo.cihazlar(CihazId) ON DELETE CASCADE,
        -- Excel'deki kirmizi grup basliklari: 'MEKANIK', 'SULAMA ve
        -- DEVIRDAIM SISTEMI', 'ELEKTRONIK', 'GENEL'... serbest metin.
        Grup            NVARCHAR(100) NULL,
        -- 'Malzeme' | 'İşçilik' | 'Dış Hizmet' | 'Genel Gider'
        -- Maliyeti degistirmez, sadece cihaz kartinda dokum cikarmak icin.
        KalemTuru       NVARCHAR(20) NOT NULL
            CONSTRAINT DF_cihaz_recete_KalemTuru DEFAULT N'Malzeme',
        KalemAdi        NVARCHAR(300) NOT NULL,
        Adet            DECIMAL(18,3) NOT NULL CONSTRAINT DF_cihaz_recete_Adet DEFAULT 1,
        Birim           NVARCHAR(20) NULL,
        -- Maliyet KENDI para biriminde saklanir, TL'ye cakilmaz: Excel'de
        -- dolar kuru 50 TL olarak sabit yazildigi icin kur degistiginde kar
        -- orani oldugundan yuksek gorunuyordu. BirimFiyatTL bu kurla
        -- hesaplanmis "o gunku" degerdir; guncel kurla karsilastirma ekranda
        -- yapilir.
        BirimFiyat      DECIMAL(18,4) NOT NULL CONSTRAINT DF_cihaz_recete_BirimFiyat DEFAULT 0,
        ParaBirimi      NVARCHAR(5) NOT NULL CONSTRAINT DF_cihaz_recete_ParaBirimi DEFAULT N'TL',
        Kur             DECIMAL(18,4) NOT NULL CONSTRAINT DF_cihaz_recete_Kur DEFAULT 1,
        BirimFiyatTL    DECIMAL(18,2) NOT NULL CONSTRAINT DF_cihaz_recete_BirimFiyatTL DEFAULT 0,
        ToplamTutarTL   DECIMAL(18,2) NOT NULL CONSTRAINT DF_cihaz_recete_ToplamTutarTL DEFAULT 0,
        -- Excel'deki "FIRMA" sutunu (DEM-ER HID., UZEL DISLI, aydoganlar...).
        -- Tedarikci karti varsa TedarikciId de doldurulur; yoksa serbest ad.
        TedarikciAdi    NVARCHAR(250) NULL,
        TedarikciId     INT NULL REFERENCES dbo.tedarikciler(TedarikciId),
        -- Kalemin en son hangi satinalmadan guncellendigi (opsiyonel bag).
        SonSatinalmaId  INT NULL REFERENCES dbo.satinalmalar(SatinalmaId),
        FiyatTarihi     DATE NULL,
        SiraNo          INT NOT NULL CONSTRAINT DF_cihaz_recete_SiraNo DEFAULT 0,
        Aciklama        NVARCHAR(500) NULL
    );

    CREATE NONCLUSTERED INDEX IX_cihaz_recete_CihazId_SiraNo
        ON dbo.cihaz_recete_kalemleri (CihazId, SiraNo);
    -- "Bu parcayi en son kactan almistik?" onerisi icin.
    CREATE NONCLUSTERED INDEX IX_cihaz_recete_KalemAdi
        ON dbo.cihaz_recete_kalemleri (KalemAdi);
END
GO

-- ----------------------------------------------------------------------------
-- 5) dbo.cihaz_maliyet_gecmisi : ikinci Excel sayfasinin otomatik hali
--
-- Excel'de bu tablo ELLE dolduruluyordu (maliyeti degisen urun / urunun eski
-- maliyeti / eski toplam / yeni toplam / kar orani / yeni satis fiyati /
-- tarih / firma). Burada program yazar: bir recete kaleminin fiyati
-- degistiginde satir kendiliginden duser.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.cihaz_maliyet_gecmisi', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.cihaz_maliyet_gecmisi (
        GecmisId            INT IDENTITY(1,1) PRIMARY KEY,
        CihazId             INT NOT NULL REFERENCES dbo.cihazlar(CihazId) ON DELETE CASCADE,
        -- Kalem sonradan silinebilecegi icin adi da METIN olarak kopyalanir:
        -- gecmis satiri kendi basina okunabilir kalsin.
        ReceteKalemId       INT NULL,
        DegisenKalemAdi     NVARCHAR(300) NULL,
        EskiBirimFiyatTL    DECIMAL(18,2) NULL,
        YeniBirimFiyatTL    DECIMAL(18,2) NULL,
        EskiToplamMaliyetTL DECIMAL(18,2) NOT NULL,
        YeniToplamMaliyetTL DECIMAL(18,2) NOT NULL,
        -- Degisiklik anindaki kar orani ve ondan cikan satis fiyati.
        -- Oran cihazda sonradan degisse bile bu satir degismez.
        KarOrani            DECIMAL(6,2) NOT NULL,
        YeniSatisFiyatiTL   DECIMAL(18,2) NOT NULL,
        TedarikciAdi        NVARCHAR(250) NULL,
        -- Degisiklik bir satinalmadan geldiyse kaynagi.
        SatinalmaId         INT NULL REFERENCES dbo.satinalmalar(SatinalmaId),
        KullaniciId         INT NULL REFERENCES dbo.kullanicilar(KullaniciId),
        DegisiklikTarihi    DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
        Aciklama            NVARCHAR(500) NULL
    );

    CREATE NONCLUSTERED INDEX IX_cihaz_maliyet_gecmisi_CihazId_Tarih
        ON dbo.cihaz_maliyet_gecmisi (CihazId, DegisiklikTarihi DESC);
END
GO

-- ----------------------------------------------------------------------------
-- 6) Siparis listelerinin indeksleri
--    "Bekleyen siparisler" ekrani Durum + BeklenenTeslimTarihi uzerinden,
--    "Satinalma gecmisi" ekrani SatinalmaTarihi uzerinden calisir.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_satinalmalar_Durum_BeklenenTeslimTarihi'
      AND object_id = OBJECT_ID(N'dbo.satinalmalar')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_satinalmalar_Durum_BeklenenTeslimTarihi
        ON dbo.satinalmalar (Durum, BeklenenTeslimTarihi);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_satinalmalar_SatinalmaTarihi'
      AND object_id = OBJECT_ID(N'dbo.satinalmalar')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_satinalmalar_SatinalmaTarihi
        ON dbo.satinalmalar (SatinalmaTarihi DESC);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_satinalma_kalemleri_SatinalmaId'
      AND object_id = OBJECT_ID(N'dbo.satinalma_kalemleri')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_satinalma_kalemleri_SatinalmaId
        ON dbo.satinalma_kalemleri (SatinalmaId);
END
GO

-- "Bu parcayi daha once nereden, kactan almistik?" onerisi icin.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_satinalma_kalemleri_KalemAdi'
      AND object_id = OBJECT_ID(N'dbo.satinalma_kalemleri')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_satinalma_kalemleri_KalemAdi
        ON dbo.satinalma_kalemleri (KalemAdi);
END
GO

PRINT N'17 - Satinalma siparis takibi + cihaz maliyet receteleri kuruldu (veya zaten mevcuttu).';
GO
