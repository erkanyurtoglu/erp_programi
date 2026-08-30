#pragma once

#include <QVariantList>
#include <QString>

class QSqlDatabase;

// Musteri Ver ekranindaki canli arama (firma + urun) sorgularinin gerceklestirdigi
// SQL mantigi. Hem Database (ana baglanti, senkron/eski cagri yolu icin) hem de
// AramaWorker (ayri thread + ayri baglanti, TeklifVerPage'in async arama yolu icin)
// tarafindan paylasilir -- boylece sorgu SQL'i tek yerde tanimli kalir.
QVariantList musteriAraSorgusu(QSqlDatabase &db, const QString &arama, int limit);
QVariantList urunAraSorgusu(QSqlDatabase &db, const QString &arama, int limit, const QString &dil);
