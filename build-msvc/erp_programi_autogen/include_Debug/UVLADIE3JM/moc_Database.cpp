/****************************************************************************
** Meta object code from reading C++ file 'Database.h'
**
** Created by: The Qt Meta Object Compiler version 68 (Qt 6.7.3)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include "../../../../src/Database.h"
#include <QtCore/qmetatype.h>

#include <QtCore/qtmochelpers.h>

#include <memory>


#include <QtCore/qxptype_traits.h>
#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'Database.h' doesn't include <QObject>."
#elif Q_MOC_OUTPUT_REVISION != 68
#error "This file was generated using the moc from 6.7.3. It"
#error "cannot be used with the include files from this version of Qt."
#error "(The moc has changed too much.)"
#endif

#ifndef Q_CONSTINIT
#define Q_CONSTINIT
#endif

QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
QT_WARNING_DISABLE_GCC("-Wuseless-cast")
namespace {

#ifdef QT_MOC_HAS_STRINGDATA
struct qt_meta_stringdata_CLASSDatabaseENDCLASS_t {};
constexpr auto qt_meta_stringdata_CLASSDatabaseENDCLASS = QtMocHelpers::stringData(
    "Database",
    "musteriSonuclariHazir",
    "",
    "arama",
    "sonuclar",
    "urunSonuclariHazir",
    "dil",
    "girisYap",
    "kullaniciAdi",
    "sifre",
    "gecmisTekliflerGetir",
    "tarihFiltresi",
    "baslangicTarihi",
    "bitisTarihi",
    "sayfaNo",
    "sayfaBoyutu",
    "durumFiltresi",
    "teklifSil",
    "teklifId",
    "musteriAraBaslat",
    "limit",
    "urunAraBaslat",
    "teklifKaydet",
    "teklif",
    "teklifDurumGuncelle",
    "durum",
    "redSebebi",
    "musteriListesiGetir",
    "musteriEkle",
    "musteri",
    "musteriGuncelle",
    "musteriId",
    "musteriSil",
    "urunListesiGetir",
    "urunEkle",
    "urun",
    "urunGuncelle",
    "urunId",
    "urunSil",
    "rolListesiGetir",
    "personelListesiGetir",
    "personelEkle",
    "personel",
    "personelGuncelle",
    "kullaniciId",
    "personelAktifDurumDegistir",
    "aktif",
    "teklifPdfOlustur",
    "satisSozlesmesiOlustur",
    "baglantiHazir"
);
#else  // !QT_MOC_HAS_STRINGDATA
#error "qtmochelpers.h not found or too old."
#endif // !QT_MOC_HAS_STRINGDATA
} // unnamed namespace

Q_CONSTINIT static const uint qt_meta_data_CLASSDatabaseENDCLASS[] = {

 // content:
      12,       // revision
       0,       // classname
       0,    0, // classinfo
      33,   14, // methods
       1,  387, // properties
       0,    0, // enums/sets
       0,    0, // constructors
       0,       // flags
       2,       // signalCount

 // signals: name, argc, parameters, tag, flags, initial metatype offsets
       1,    2,  212,    2, 0x06,    2 /* Public */,
       5,    3,  217,    2, 0x06,    5 /* Public */,

 // methods: name, argc, parameters, tag, flags, initial metatype offsets
       7,    2,  224,    2, 0x02,    9 /* Public */,
      10,    7,  229,    2, 0x02,   12 /* Public */,
      10,    6,  244,    2, 0x22,   20 /* Public | MethodCloned */,
      10,    5,  257,    2, 0x22,   27 /* Public | MethodCloned */,
      17,    1,  268,    2, 0x02,   33 /* Public */,
      19,    2,  271,    2, 0x02,   35 /* Public */,
      19,    1,  276,    2, 0x22,   38 /* Public | MethodCloned */,
      21,    3,  279,    2, 0x02,   40 /* Public */,
      21,    2,  286,    2, 0x22,   44 /* Public | MethodCloned */,
      21,    1,  291,    2, 0x22,   47 /* Public | MethodCloned */,
      22,    1,  294,    2, 0x02,   49 /* Public */,
      24,    3,  297,    2, 0x02,   51 /* Public */,
      24,    2,  304,    2, 0x22,   55 /* Public | MethodCloned */,
      27,    3,  309,    2, 0x02,   58 /* Public */,
      27,    2,  316,    2, 0x22,   62 /* Public | MethodCloned */,
      28,    1,  321,    2, 0x02,   65 /* Public */,
      30,    2,  324,    2, 0x02,   67 /* Public */,
      32,    1,  329,    2, 0x02,   70 /* Public */,
      33,    3,  332,    2, 0x02,   72 /* Public */,
      33,    2,  339,    2, 0x22,   76 /* Public | MethodCloned */,
      34,    1,  344,    2, 0x02,   79 /* Public */,
      36,    2,  347,    2, 0x02,   81 /* Public */,
      38,    1,  352,    2, 0x02,   84 /* Public */,
      39,    0,  355,    2, 0x02,   86 /* Public */,
      40,    3,  356,    2, 0x02,   87 /* Public */,
      40,    2,  363,    2, 0x22,   91 /* Public | MethodCloned */,
      41,    1,  368,    2, 0x02,   94 /* Public */,
      43,    2,  371,    2, 0x02,   96 /* Public */,
      45,    2,  376,    2, 0x02,   99 /* Public */,
      47,    1,  381,    2, 0x02,  102 /* Public */,
      48,    1,  384,    2, 0x02,  104 /* Public */,

 // signals: parameters
    QMetaType::Void, QMetaType::QString, QMetaType::QVariantList,    3,    4,
    QMetaType::Void, QMetaType::QString, QMetaType::QString, QMetaType::QVariantList,    3,    6,    4,

 // methods: parameters
    QMetaType::QVariantMap, QMetaType::QString, QMetaType::QString,    8,    9,
    QMetaType::QVariantMap, QMetaType::QString, QMetaType::QString, QMetaType::QString, QMetaType::QString, QMetaType::Int, QMetaType::Int, QMetaType::QString,    3,   11,   12,   13,   14,   15,   16,
    QMetaType::QVariantMap, QMetaType::QString, QMetaType::QString, QMetaType::QString, QMetaType::QString, QMetaType::Int, QMetaType::Int,    3,   11,   12,   13,   14,   15,
    QMetaType::QVariantMap, QMetaType::QString, QMetaType::QString, QMetaType::QString, QMetaType::QString, QMetaType::Int,    3,   11,   12,   13,   14,
    QMetaType::Bool, QMetaType::Int,   18,
    QMetaType::Void, QMetaType::QString, QMetaType::Int,    3,   20,
    QMetaType::Void, QMetaType::QString,    3,
    QMetaType::Void, QMetaType::QString, QMetaType::Int, QMetaType::QString,    3,   20,    6,
    QMetaType::Void, QMetaType::QString, QMetaType::Int,    3,   20,
    QMetaType::Void, QMetaType::QString,    3,
    QMetaType::QVariantMap, QMetaType::QVariantMap,   23,
    QMetaType::Bool, QMetaType::Int, QMetaType::QString, QMetaType::QString,   18,   25,   26,
    QMetaType::Bool, QMetaType::Int, QMetaType::QString,   18,   25,
    QMetaType::QVariantMap, QMetaType::QString, QMetaType::Int, QMetaType::Int,    3,   14,   15,
    QMetaType::QVariantMap, QMetaType::QString, QMetaType::Int,    3,   14,
    QMetaType::QVariantMap, QMetaType::QVariantMap,   29,
    QMetaType::QVariantMap, QMetaType::Int, QMetaType::QVariantMap,   31,   29,
    QMetaType::QVariantMap, QMetaType::Int,   31,
    QMetaType::QVariantMap, QMetaType::QString, QMetaType::Int, QMetaType::Int,    3,   14,   15,
    QMetaType::QVariantMap, QMetaType::QString, QMetaType::Int,    3,   14,
    QMetaType::QVariantMap, QMetaType::QVariantMap,   35,
    QMetaType::QVariantMap, QMetaType::Int, QMetaType::QVariantMap,   37,   35,
    QMetaType::QVariantMap, QMetaType::Int,   37,
    QMetaType::QVariantList,
    QMetaType::QVariantMap, QMetaType::QString, QMetaType::Int, QMetaType::Int,    3,   14,   15,
    QMetaType::QVariantMap, QMetaType::QString, QMetaType::Int,    3,   14,
    QMetaType::QVariantMap, QMetaType::QVariantMap,   42,
    QMetaType::QVariantMap, QMetaType::Int, QMetaType::QVariantMap,   44,   42,
    QMetaType::Bool, QMetaType::Int, QMetaType::Bool,   44,   46,
    QMetaType::QVariantMap, QMetaType::Int,   18,
    QMetaType::QVariantMap, QMetaType::QVariantMap,   23,

 // properties: name, type, flags
      49, QMetaType::Bool, 0x00015401, uint(-1), 0,

       0        // eod
};

Q_CONSTINIT const QMetaObject Database::staticMetaObject = { {
    QMetaObject::SuperData::link<QObject::staticMetaObject>(),
    qt_meta_stringdata_CLASSDatabaseENDCLASS.offsetsAndSizes,
    qt_meta_data_CLASSDatabaseENDCLASS,
    qt_static_metacall,
    nullptr,
    qt_incomplete_metaTypeArray<qt_meta_stringdata_CLASSDatabaseENDCLASS_t,
        // property 'baglantiHazir'
        QtPrivate::TypeAndForceComplete<bool, std::true_type>,
        // Q_OBJECT / Q_GADGET
        QtPrivate::TypeAndForceComplete<Database, std::true_type>,
        // method 'musteriSonuclariHazir'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QVariantList &, std::false_type>,
        // method 'urunSonuclariHazir'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QVariantList &, std::false_type>,
        // method 'girisYap'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        // method 'gecmisTekliflerGetir'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        // method 'gecmisTekliflerGetir'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'gecmisTekliflerGetir'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'teklifSil'
        QtPrivate::TypeAndForceComplete<bool, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'musteriAraBaslat'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'musteriAraBaslat'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        // method 'urunAraBaslat'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        // method 'urunAraBaslat'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'urunAraBaslat'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        // method 'teklifKaydet'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QVariantMap &, std::false_type>,
        // method 'teklifDurumGuncelle'
        QtPrivate::TypeAndForceComplete<bool, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        // method 'teklifDurumGuncelle'
        QtPrivate::TypeAndForceComplete<bool, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        // method 'musteriListesiGetir'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'musteriListesiGetir'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'musteriEkle'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QVariantMap &, std::false_type>,
        // method 'musteriGuncelle'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QVariantMap &, std::false_type>,
        // method 'musteriSil'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'urunListesiGetir'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'urunListesiGetir'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'urunEkle'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QVariantMap &, std::false_type>,
        // method 'urunGuncelle'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QVariantMap &, std::false_type>,
        // method 'urunSil'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'rolListesiGetir'
        QtPrivate::TypeAndForceComplete<QVariantList, std::false_type>,
        // method 'personelListesiGetir'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'personelListesiGetir'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'personelEkle'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QVariantMap &, std::false_type>,
        // method 'personelGuncelle'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QVariantMap &, std::false_type>,
        // method 'personelAktifDurumDegistir'
        QtPrivate::TypeAndForceComplete<bool, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        QtPrivate::TypeAndForceComplete<bool, std::false_type>,
        // method 'teklifPdfOlustur'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'satisSozlesmesiOlustur'
        QtPrivate::TypeAndForceComplete<QVariantMap, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QVariantMap &, std::false_type>
    >,
    nullptr
} };

void Database::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    if (_c == QMetaObject::InvokeMetaMethod) {
        auto *_t = static_cast<Database *>(_o);
        (void)_t;
        switch (_id) {
        case 0: _t->musteriSonuclariHazir((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QVariantList>>(_a[2]))); break;
        case 1: _t->urunSonuclariHazir((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[2])),(*reinterpret_cast< std::add_pointer_t<QVariantList>>(_a[3]))); break;
        case 2: { QVariantMap _r = _t->girisYap((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[2])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 3: { QVariantMap _r = _t->gecmisTekliflerGetir((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[2])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[3])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[4])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[5])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[6])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[7])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 4: { QVariantMap _r = _t->gecmisTekliflerGetir((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[2])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[3])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[4])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[5])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[6])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 5: { QVariantMap _r = _t->gecmisTekliflerGetir((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[2])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[3])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[4])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[5])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 6: { bool _r = _t->teklifSil((*reinterpret_cast< std::add_pointer_t<int>>(_a[1])));
            if (_a[0]) *reinterpret_cast< bool*>(_a[0]) = std::move(_r); }  break;
        case 7: _t->musteriAraBaslat((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[2]))); break;
        case 8: _t->musteriAraBaslat((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1]))); break;
        case 9: _t->urunAraBaslat((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[2])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[3]))); break;
        case 10: _t->urunAraBaslat((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[2]))); break;
        case 11: _t->urunAraBaslat((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1]))); break;
        case 12: { QVariantMap _r = _t->teklifKaydet((*reinterpret_cast< std::add_pointer_t<QVariantMap>>(_a[1])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 13: { bool _r = _t->teklifDurumGuncelle((*reinterpret_cast< std::add_pointer_t<int>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[2])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[3])));
            if (_a[0]) *reinterpret_cast< bool*>(_a[0]) = std::move(_r); }  break;
        case 14: { bool _r = _t->teklifDurumGuncelle((*reinterpret_cast< std::add_pointer_t<int>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[2])));
            if (_a[0]) *reinterpret_cast< bool*>(_a[0]) = std::move(_r); }  break;
        case 15: { QVariantMap _r = _t->musteriListesiGetir((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[2])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[3])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 16: { QVariantMap _r = _t->musteriListesiGetir((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[2])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 17: { QVariantMap _r = _t->musteriEkle((*reinterpret_cast< std::add_pointer_t<QVariantMap>>(_a[1])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 18: { QVariantMap _r = _t->musteriGuncelle((*reinterpret_cast< std::add_pointer_t<int>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QVariantMap>>(_a[2])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 19: { QVariantMap _r = _t->musteriSil((*reinterpret_cast< std::add_pointer_t<int>>(_a[1])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 20: { QVariantMap _r = _t->urunListesiGetir((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[2])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[3])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 21: { QVariantMap _r = _t->urunListesiGetir((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[2])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 22: { QVariantMap _r = _t->urunEkle((*reinterpret_cast< std::add_pointer_t<QVariantMap>>(_a[1])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 23: { QVariantMap _r = _t->urunGuncelle((*reinterpret_cast< std::add_pointer_t<int>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QVariantMap>>(_a[2])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 24: { QVariantMap _r = _t->urunSil((*reinterpret_cast< std::add_pointer_t<int>>(_a[1])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 25: { QVariantList _r = _t->rolListesiGetir();
            if (_a[0]) *reinterpret_cast< QVariantList*>(_a[0]) = std::move(_r); }  break;
        case 26: { QVariantMap _r = _t->personelListesiGetir((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[2])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[3])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 27: { QVariantMap _r = _t->personelListesiGetir((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[2])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 28: { QVariantMap _r = _t->personelEkle((*reinterpret_cast< std::add_pointer_t<QVariantMap>>(_a[1])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 29: { QVariantMap _r = _t->personelGuncelle((*reinterpret_cast< std::add_pointer_t<int>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QVariantMap>>(_a[2])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 30: { bool _r = _t->personelAktifDurumDegistir((*reinterpret_cast< std::add_pointer_t<int>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<bool>>(_a[2])));
            if (_a[0]) *reinterpret_cast< bool*>(_a[0]) = std::move(_r); }  break;
        case 31: { QVariantMap _r = _t->teklifPdfOlustur((*reinterpret_cast< std::add_pointer_t<int>>(_a[1])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        case 32: { QVariantMap _r = _t->satisSozlesmesiOlustur((*reinterpret_cast< std::add_pointer_t<QVariantMap>>(_a[1])));
            if (_a[0]) *reinterpret_cast< QVariantMap*>(_a[0]) = std::move(_r); }  break;
        default: ;
        }
    } else if (_c == QMetaObject::IndexOfMethod) {
        int *result = reinterpret_cast<int *>(_a[0]);
        {
            using _t = void (Database::*)(const QString & , const QVariantList & );
            if (_t _q_method = &Database::musteriSonuclariHazir; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 0;
                return;
            }
        }
        {
            using _t = void (Database::*)(const QString & , const QString & , const QVariantList & );
            if (_t _q_method = &Database::urunSonuclariHazir; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 1;
                return;
            }
        }
    } else if (_c == QMetaObject::ReadProperty) {
        auto *_t = static_cast<Database *>(_o);
        (void)_t;
        void *_v = _a[0];
        switch (_id) {
        case 0: *reinterpret_cast< bool*>(_v) = _t->baglantiHazirMi(); break;
        default: break;
        }
    } else if (_c == QMetaObject::WriteProperty) {
    } else if (_c == QMetaObject::ResetProperty) {
    } else if (_c == QMetaObject::BindableProperty) {
    }
}

const QMetaObject *Database::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *Database::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_meta_stringdata_CLASSDatabaseENDCLASS.stringdata0))
        return static_cast<void*>(this);
    return QObject::qt_metacast(_clname);
}

int Database::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QObject::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 33)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 33;
    } else if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 33)
            *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType();
        _id -= 33;
    }else if (_c == QMetaObject::ReadProperty || _c == QMetaObject::WriteProperty
            || _c == QMetaObject::ResetProperty || _c == QMetaObject::BindableProperty
            || _c == QMetaObject::RegisterPropertyMetaType) {
        qt_static_metacall(this, _c, _id, _a);
        _id -= 1;
    }
    return _id;
}

// SIGNAL 0
void Database::musteriSonuclariHazir(const QString & _t1, const QVariantList & _t2)
{
    void *_a[] = { nullptr, const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t1))), const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t2))) };
    QMetaObject::activate(this, &staticMetaObject, 0, _a);
}

// SIGNAL 1
void Database::urunSonuclariHazir(const QString & _t1, const QString & _t2, const QVariantList & _t3)
{
    void *_a[] = { nullptr, const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t1))), const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t2))), const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t3))) };
    QMetaObject::activate(this, &staticMetaObject, 1, _a);
}
QT_WARNING_POP
