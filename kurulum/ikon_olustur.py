# pdf_sablonlari/assets/ikon.png'den exe/kisayol/kurulum simgesi (assets/liya.ico) uretir.
# Kullanim: python kurulum/ikon_olustur.py   (kurulum_olustur.ps1 bunu kendisi cagirir)
from pathlib import Path

from PIL import Image

KOK = Path(__file__).resolve().parent.parent
KAYNAK = KOK / "pdf_sablonlari" / "assets" / "ikon.png"
HEDEF = KOK / "assets" / "liya.ico"
BOYUTLAR = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]

resim = Image.open(KAYNAK).convert("RGBA")
# Kare degilse ortalayip seffaf kenarla kareye tamamla.
kenar = max(resim.size)
kare = Image.new("RGBA", (kenar, kenar), (0, 0, 0, 0))
kare.paste(resim, ((kenar - resim.width) // 2, (kenar - resim.height) // 2))

# Her boyut ayri ayri yuksek kaliteli kucultulur (Pillow'un otomatik kucultmesi
# kucuk boyutlarda daha bulanik kaliyor).
katmanlar = [kare.resize((b, b), Image.LANCZOS) for b in BOYUTLAR]
katmanlar[-1].save(HEDEF, format="ICO", sizes=[(b, b) for b in BOYUTLAR],
                   append_images=katmanlar[:-1])
print(f"{HEDEF} yazildi ({', '.join(str(b) for b in BOYUTLAR)} px)")
