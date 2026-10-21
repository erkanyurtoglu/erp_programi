"""Tum proje kaynak kodlarini tek bir PDF'e aktarir.

Kullanim:  python code_export/export_kod.py
Cikti:     code_export/erp_programi_kodlar.pdf
"""

import os
import subprocess
import sys
import textwrap
from datetime import datetime

from reportlab.lib.colors import HexColor
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    PageBreak,
    PageTemplate,
    Paragraph,
    Preformatted,
    Spacer,
)

PROJE_DIZINI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CIKTI = os.path.join(PROJE_DIZINI, "code_export", "erp_programi_kodlar.pdf")

# PDF'e alinacak metin tabanli dosya uzantilari
UZANTILAR = {
    ".cpp", ".h", ".hpp", ".c", ".cc",
    ".qml", ".js",
    ".sql",
    ".txt", ".json", ".md",
    ".html", ".css",
    ".py", ".ps1", ".sh",
    ".qrc", ".ui", ".cmake", ".pro",
}
# Isimle eslesen ek dosyalar
AD_ILE = {"CMakeLists.txt", "CMakePresets.json", ".gitignore", ".gitattributes"}
# Atlanacaklar
ATLA = {"aqtinstall.log"}

SATIR_GENISLIGI = 112  # 7pt Consolas icin A4 genisligine sigan karakter sayisi


def fontlari_yukle():
    """Turkce karakter destekli monospace font kaydeder."""
    adaylar = [
        ("Kod", r"C:\Windows\Fonts\consola.ttf"),
        ("Kod-Bold", r"C:\Windows\Fonts\consolab.ttf"),
    ]
    for ad, yol in adaylar:
        if not os.path.exists(yol):
            return "Courier", "Courier-Bold"
        pdfmetrics.registerFont(TTFont(ad, yol))
    return "Kod", "Kod-Bold"


def dosyalari_bul():
    """git ls-files cikisindan PDF'e girecek dosyalari siralar."""
    try:
        # --others --exclude-standard: henuz commit edilmemis yeni dosyalar da girsin
        cikti = subprocess.check_output(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
            cwd=PROJE_DIZINI,
            text=True,
            encoding="utf-8",
        )
        adaylar = sorted(set(cikti.splitlines()))
    except Exception:
        adaylar = []
        for kok, dizinler, dosyalar in os.walk(PROJE_DIZINI):
            dizinler[:] = [d for d in dizinler if d not in {".git", "build", "code_export"}]
            for d in dosyalar:
                tam = os.path.join(kok, d)
                adaylar.append(os.path.relpath(tam, PROJE_DIZINI).replace("\\", "/"))

    secilen = []
    for yol in adaylar:
        ad = os.path.basename(yol)
        if ad in ATLA or yol.startswith("code_export/"):
            continue
        if ad in AD_ILE or os.path.splitext(ad)[1].lower() in UZANTILAR:
            secilen.append(yol)

    # Okunabilir sira: kaynak kod -> qml -> veritabani -> digerleri
    oncelik = {".cpp": 0, ".h": 0, ".hpp": 0, ".qml": 1, ".sql": 2}
    secilen.sort(key=lambda y: (oncelik.get(os.path.splitext(y)[1].lower(), 3), y.lower()))
    return secilen


def main():
    kod_font, kod_bold = fontlari_yukle()
    dosyalar = dosyalari_bul()

    baslik_stili = ParagraphStyle(
        "DosyaBasligi",
        fontName=kod_bold,
        fontSize=11,
        leading=14,
        textColor=HexColor("#1a3d6d"),
        spaceAfter=4,
    )
    bilgi_stili = ParagraphStyle(
        "Bilgi", fontName=kod_font, fontSize=8, leading=11, textColor=HexColor("#666666")
    )
    kapak_stili = ParagraphStyle(
        "Kapak", fontName=kod_bold, fontSize=22, leading=28, alignment=TA_LEFT
    )
    icindekiler_stili = ParagraphStyle(
        "Icindekiler", fontName=kod_font, fontSize=9, leading=13
    )
    kod_stili = ParagraphStyle(
        "Kod", fontName=kod_font, fontSize=7, leading=8.6, textColor=HexColor("#111111")
    )

    class Belge(BaseDocTemplate):
        def afterFlowable(self, flowable):
            etiket = getattr(flowable, "_dosyaYolu", None)
            if etiket:
                self.canv.bookmarkPage(etiket)
                self.canv.addOutlineEntry(etiket, etiket, level=0)

    belge = Belge(
        CIKTI,
        pagesize=A4,
        leftMargin=12 * mm,
        rightMargin=10 * mm,
        topMargin=12 * mm,
        bottomMargin=14 * mm,
        title="ERP Programi - Kaynak Kodlar",
        author="erp_programi",
    )

    def sayfa_alt(canvas, doc):
        canvas.saveState()
        canvas.setFont(kod_font, 7)
        canvas.setFillColor(HexColor("#888888"))
        canvas.drawRightString(A4[0] - 10 * mm, 7 * mm, f"Sayfa {doc.page}")
        canvas.drawString(12 * mm, 7 * mm, "erp_programi - kaynak kod dokumu")
        canvas.restoreState()

    cerceve = Frame(
        belge.leftMargin,
        belge.bottomMargin,
        belge.width,
        belge.height,
        id="govde",
    )
    belge.addPageTemplates([PageTemplate(id="std", frames=[cerceve], onPage=sayfa_alt)])

    akis = []
    # --- Kapak ---
    akis.append(Spacer(1, 40 * mm))
    akis.append(Paragraph("ERP Programi", kapak_stili))
    akis.append(Paragraph("Kaynak Kod Dokumu", kapak_stili))
    akis.append(Spacer(1, 8 * mm))
    akis.append(
        Paragraph(
            f"Olusturulma: {datetime.now():%d.%m.%Y %H:%M}<br/>"
            f"Dosya sayisi: {len(dosyalar)}",
            bilgi_stili,
        )
    )
    akis.append(PageBreak())

    # --- Icindekiler ---
    akis.append(Paragraph("Icindekiler", baslik_stili))
    akis.append(Spacer(1, 3 * mm))
    for i, yol in enumerate(dosyalar, 1):
        akis.append(
            Paragraph(f'{i:>3}. <a href="#{yol}" color="#1a3d6d">{yol}</a>', icindekiler_stili)
        )
    akis.append(PageBreak())

    # --- Dosya icerikleri ---
    for i, yol in enumerate(dosyalar, 1):
        tam = os.path.join(PROJE_DIZINI, yol)
        try:
            with open(tam, "r", encoding="utf-8", errors="replace") as f:
                icerik = f.read()
        except OSError as hata:
            icerik = f"[okunamadi: {hata}]"

        satirlar = icerik.replace("\t", "    ").splitlines() or [""]

        baslik = Paragraph(f"{i}. {yol}", baslik_stili)
        baslik._dosyaYolu = yol
        akis.append(baslik)
        akis.append(
            Paragraph(f"{len(satirlar)} satir &middot; {os.path.getsize(tam)} bayt", bilgi_stili)
        )
        akis.append(Spacer(1, 2 * mm))

        # Satir numarali ve sarmalanmis kod blogu
        blok = []
        for no, satir in enumerate(satirlar, 1):
            parcalar = textwrap.wrap(
                satir, SATIR_GENISLIGI, drop_whitespace=False, replace_whitespace=False
            ) or [""]
            for j, parca in enumerate(parcalar):
                etiket = f"{no:>5} | " if j == 0 else "      | "
                blok.append(etiket + parca)

        # Buyuk dosyalari parcalara bolerek bellek/sayfa tasmasini onle
        ADIM = 60
        for bas in range(0, len(blok), ADIM):
            akis.append(Preformatted("\n".join(blok[bas : bas + ADIM]), kod_stili))
        akis.append(PageBreak())

    belge.build(akis)
    print(f"Olusturuldu: {CIKTI}")
    print(f"Dosya sayisi: {len(dosyalar)}")


if __name__ == "__main__":
    sys.exit(main())
