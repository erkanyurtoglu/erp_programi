cmake_minimum_required(VERSION 3.21)
project(erp_programi VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Quick Qml Sql Network WebEngineCore Pdf)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(erp_programi
    main.cpp
    src/Database.h
    src/Database.cpp
    src/AramaWorker.h
    src/AramaWorker.cpp
    src/AramaSorgulari.h
    src/AramaSorgulari.cpp
    src/SqlYardimcilari.h
    src/SqlYardimcilari.cpp
    src/TeklifPdfOlusturucu.h
    src/TeklifPdfOlusturucu.cpp
    src/PdfOnizleyici.h
    src/PdfOnizleyici.cpp
    src/Tanilama.h
    src/Tanilama.cpp
    src/KurServisi.h
    src/KurServisi.cpp
)

# Exe dosyasinin (Gezgin / masaustu kisayolu) simgesi.
if(WIN32)
    target_sources(erp_programi PRIVATE assets/erp_programi.rc)
endif()

# Logo tek kaynaktan (PDF sablonlarindaki dosya) okunur; QML'de ve pencere
# simgesinde "qrc:/qt/qml/erp_programi/logo.png" olarak kullanilir.
set_source_files_properties(pdf_sablonlari/assets/logo.png PROPERTIES
    QT_RESOURCE_ALIAS logo.png
)

target_compile_definitions(erp_programi PRIVATE
    $<$<CONFIG:Debug>:PDF_SABLON_KAYNAK_DIZINI="${CMAKE_SOURCE_DIR}/pdf_sablonlari">
)

add_custom_command(TARGET erp_programi POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_SOURCE_DIR}/pdf_sablonlari"
            "$<TARGET_FILE_DIR:erp_programi>/pdf_sablonlari"
    COMMENT "PDF sablonlari (pdf_sablonlari/) exe yanina kopyalaniyor"
)

# Theme.qml bir "pragma Singleton" dosyasidir; QML tarafinda "Theme.xxx" olarak
# import edilebilmesi icin QML tipini singleton olarak isaretliyoruz.
# ONEMLI: bu, qt_add_qml_module() CAGRISINDAN ONCE yapilmali -- qt_add_qml_module
# QML_FILES listesini cagri aninda isliyor, sonradan set edilen property'yi gormuyor.
set_source_files_properties(qml/Theme.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

# SayiBicimi.qml de ayni sekilde bir singleton'dir (Turkce sayi bicimi
# yardimcilari: "SayiBicimi.ayikla(...)", "SayiBicimi.bicimle(...)").
set_source_files_properties(qml/SayiBicimi.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

# PdfOnizleme.qml: sayfalarin "PdfOnizleme.ac(pdf, baslik)" ile Main.qml'deki
# tek onizleme penceresini acmasini saglayan singleton.
set_source_files_properties(qml/PdfOnizleme.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

# SatinalmaBicim.qml: satinalma ekranlarinin ortak gosterim kurallari
# (belge numaralari, durum renkleri, para/tarih bicimi).
set_source_files_properties(qml/SatinalmaBicim.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(erp_programi
    URI erp_programi
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/SayiBicimi.qml
        qml/PdfOnizleme.qml
        qml/SatinalmaBicim.qml
        qml/pages/GecmisTekliflerPage.qml
        qml/pages/GirisPage.qml
        qml/pages/AnaMenuPage.qml
        qml/pages/TeklifVerPage.qml
        qml/pages/SatisModuluPage.qml
        qml/pages/MusterilerimPage.qml
        qml/pages/UrunlerimPage.qml
        qml/pages/PersonellerimPage.qml
        qml/pages/SatinAlmaModuluPage.qml
        qml/pages/TedarikcilerimPage.qml
        qml/pages/SatinalmaTaleplerPage.qml
        qml/pages/TalepDuzenlePage.qml
        qml/pages/SatinalmaSiparislerPage.qml
        qml/pages/YonetimModuluPage.qml
        qml/pages/RollerYetkilerPage.qml
        qml/pages/SistemAyarlariPage.qml
        qml/pages/YonetimOzetPage.qml
        qml/pages/IslemGecmisiPage.qml
        qml/pages/CihazMaliyetleriPage.qml
        qml/pages/MuhasebeModuluPage.qml
        qml/components/ModulIkonu.qml
        qml/components/TarihTakvimi.qml
        qml/components/SozlesmeDuzenleDialog.qml
        qml/components/NotDuzenleDialog.qml
        qml/components/SevkBilgileriDialog.qml
        qml/components/SayiBicimlendirici.qml
        qml/components/TemaDialog.qml
        qml/components/TemaComboBox.qml
        qml/components/EtiketliAlan.qml
        qml/components/SifreOnayDialog.qml
        qml/components/OnayDialog.qml
        qml/components/ListeDurumu.qml
        qml/components/KisalanMetin.qml
        qml/components/TemaOnayKutusu.qml
        qml/components/PdfOnizlemeDialog.qml
        qml/components/TemaButon.qml
        qml/components/TemaDegistirici.qml
        qml/components/TemaMetinKutusu.qml
        qml/components/SayiKutusu.qml
        qml/components/OneriliMetinKutusu.qml
        qml/components/TarihSecici.qml
        qml/components/DurumRozeti.qml
        qml/components/SuzgecHapi.qml
        qml/components/SiparisEylemleri.qml
        qml/components/SiparisPencereleri.qml
    RESOURCES
        pdf_sablonlari/assets/logo.png
)

target_link_libraries(erp_programi PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::Qml
    Qt6::Sql
    # TCMB gunluk kur servisi (src/KurServisi.cpp).
    Qt6::Network
    Qt6::WebEngineCore
    # PDF onizleme: sayfalari islemcide cizen Qt PDF (pdfium).
    Qt6::Pdf
)

# Donma aninda UI thread'inin cagri yiginini sembolleriyle yazmak icin
# (bkz. Tanilama.cpp, uiYiginiYaz).
if(WIN32)
    target_link_libraries(erp_programi PRIVATE dbghelp)
endif()

set_target_properties(erp_programi PROPERTIES
    # Debug'da konsol penceresi acik kalsin (hata mesajlarini gormek icin);
    # Release'de kullaniciya yalnizca program penceresi acilsin. Release'de de
    # tum cikti gunluk dosyasina yazilmaya devam eder (bkz. Tanilama.cpp).
    WIN32_EXECUTABLE $<NOT:$<CONFIG:Debug>>
)

# Windows'ta Qt DLL'leri PATH'te olmadigi icin exe calismiyor (STATUS_DLL_NOT_FOUND).
# Her build sonrasi windeployqt calistirip gerekli DLL/QML modullerini exe'nin
# yanina otomatik kopyaliyoruz.
if(WIN32)
    find_program(WINDEPLOYQT_EXECUTABLE windeployqt HINTS "${QT6_INSTALL_PREFIX}/bin")
    if(WINDEPLOYQT_EXECUTABLE)
        add_custom_command(TARGET erp_programi POST_BUILD
            COMMAND "${WINDEPLOYQT_EXECUTABLE}"
                    --qmldir "${CMAKE_SOURCE_DIR}/qml"
                    "$<TARGET_FILE:erp_programi>"
            COMMENT "Qt DLL/QML bagimliliklari deploy ediliyor (windeployqt)"
        )
    endif()
endif()
