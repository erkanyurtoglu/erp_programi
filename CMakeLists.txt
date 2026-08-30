cmake_minimum_required(VERSION 3.21)
project(erp_programi VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Quick Qml Sql PrintSupport)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(erp_programi
    main.cpp
    src/Database.h
    src/Database.cpp
    src/AramaWorker.h
    src/AramaWorker.cpp
    src/AramaSorgulari.h
    src/AramaSorgulari.cpp
)

# Theme.qml bir "pragma Singleton" dosyasidir; QML tarafinda "Theme.xxx" olarak
# import edilebilmesi icin QML tipini singleton olarak isaretliyoruz.
# ONEMLI: bu, qt_add_qml_module() CAGRISINDAN ONCE yapilmali -- qt_add_qml_module
# QML_FILES listesini cagri aninda isliyor, sonradan set edilen property'yi gormuyor.
set_source_files_properties(qml/Theme.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(erp_programi
    URI erp_programi
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/pages/GecmisTekliflerPage.qml
        qml/pages/GirisPage.qml
        qml/pages/AnaMenuPage.qml
        qml/pages/TeklifVerPage.qml
        qml/pages/SatisModuluPage.qml
        qml/pages/MusterilerimPage.qml
        qml/pages/UrunlerimPage.qml
        qml/pages/PersonellerimPage.qml
        qml/components/ModulIkonu.qml
        qml/components/TarihTakvimi.qml
)

target_link_libraries(erp_programi PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::Qml
    Qt6::Sql
    Qt6::PrintSupport
)

set_target_properties(erp_programi PROPERTIES
    WIN32_EXECUTABLE OFF   # Konsol penceresi acik kalsin; hata mesajlarini gormek icin.
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
