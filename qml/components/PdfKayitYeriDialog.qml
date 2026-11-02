import QtQuick
import QtQuick.Dialogs

// PDF kaydedilmeden once nereye kaydedilecegini soran Windows "Farkli Kaydet"
// penceresi. Son kaydedilen klasorde, onerilen dosya adiyla acilir.
// sor(dosyaAdi, cevap): cevap(secilenUrl) -- vazgecilirse bos url ile cagrilir.
FileDialog {
    id: kok

    property var cevap: null

    function sor(dosyaAdi, yeniCevap) {
        const oneri = database.pdfKayitYeriOner(dosyaAdi)
        kok.cevap = yeniCevap
        kok.currentFolder = oneri.klasor
        kok.selectedFile = oneri.dosya
        kok.open()
    }

    function bitir(secim) {
        const c = kok.cevap
        kok.cevap = null
        if (c)
            c(secim)
    }

    title: "PDF'i Kaydet"
    fileMode: FileDialog.SaveFile
    nameFilters: ["PDF dosyası (*.pdf)"]
    defaultSuffix: "pdf"

    onAccepted: kok.bitir(kok.selectedFile)
    onRejected: kok.bitir("")
}
