# Claude Code Token Star

Claude Code'un dolan context penceresini canlı bir yıldıza dönüştürür. Token
kullanımı arttıkça yıldız büyür ve altı kozmik aşamadan geçer.

- Windows: PyCharm, IntelliJ, Android Studio, WebStorm, Rider, CLion, GoLand,
  PhpStorm, RubyMine, DataGrip, VS Code, Cursor, Visual Studio ve Eclipse
  üzerinde şeffaf overlay.
- Linux/macOS: Ghostty içinde GLSL shader.
- Yalnızca kurduğunuz projede görünür.
- Yeni Claude oturumu açmaz; açık olan oturuma bağlanır.

## Nasıl çalışıyor?

Claude Code'un status-line verisi context yüzdesini, token dökümünü ve kullanım
limitlerini küçük bir köprüye gönderir. Windows'ta WPF overlay, Linux/macOS'ta
GLSL shader bu veriyi yıldız animasyonuna çevirir. Ek API çağrısı veya token
harcaması yapmaz.

## Yıldız aşamaları

| | |
| --- | --- |
| **Red Dwarf · 0–15%**<br><img src="assets/overlay-red-dwarf.png" width="420" alt="Red Dwarf"> | **Main Sequence · 15–35%**<br><img src="assets/overlay-main-sequence.png" width="420" alt="Main Sequence"> |
| **Blue Giant · 35–55%**<br><img src="assets/overlay-blue-giant.png" width="420" alt="Blue Giant"> | **Hypergiant · 55–75%**<br><img src="assets/overlay-hypergiant.png" width="420" alt="Hypergiant"> |
| **Neutron Star · 75–90%**<br><img src="assets/overlay-neutron-star.png" width="420" alt="Neutron Star"> | **Quasar · 90–100%**<br><img src="assets/overlay-quasar.png" width="420" alt="Quasar"> |

## Windows kurulumu

Gerekenler: [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Git
ve Windows PowerShell. Python gerekmez.

1. PyCharm veya kullandığınız IDE'de projenizi açın.
2. IDE'nin terminalini açın.
3. Aşağıdaki iki komutu sırayla kopyalayıp yapıştırın:

```powershell
git clone https://github.com/0Alduin0/Claude-Code-Token-Star.git .claude-token-star
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\.claude-token-star\install.ps1
```

Hepsi bu. Installer ikinci bir Claude açmaz. Açık Claude oturumu ayarları kısa
bir gecikmeden sonra yeniden yükler; overlay aynı oturumun sonraki status
yenilemesinde çalışmaya başlar. İlk kullanımda Claude komuta güvenmek için onay
isteyebilir.

Güncellemek için aynı proje terminalinde:

```powershell
git -C .claude-token-star pull
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\.claude-token-star\install.ps1
```

## Kullanım

- Taşımak için yıldızın üzerine basıp sürükleyin.
- `MASS 85K` yaklaşık 85 bin context token anlamına gelir.
- `5H %61 | 2h 23m`, beş saatlik limitin %61'inin kullanıldığını ve yenilenme
  süresini gösterir.
- Sağdaki oka basınca `/context` benzeri token ve limit dökümü açılır.
- Başka bir projeye geçtiğinizde bu projenin yıldızı otomatik olarak gizlenir.

<img src="assets/overlay-token-details.png" width="500" alt="Açık token ve kullanım limiti menüsü">

Aşamaları gerçek token harcamadan denemek için:

```powershell
.\.claude-token-star\token-test.ps1 sweep
```

## Tarayıcıda önizleme

Windows'ta aşağıdaki tek komut yerel sunucuyu başlatır ve önizlemeyi tarayıcıda
açar. Bitirdiğinizde terminalde Enter'a basmanız sunucuyu kapatır.

```powershell
.\.claude-token-star\preview.ps1
```

Elle açılacak adres: <http://127.0.0.1:4173/preview.html>

## Windows'tan tamamen kaldırma

Projenizin terminalinde aşağıdaki iki komutu sırayla çalıştırın:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\.claude-token-star\uninstall.ps1
Remove-Item -LiteralPath .\.claude-token-star -Recurse -Force
```

İlk komut overlay ve yerel önizlemeyi durdurur; Claude status line ve hook
ayarlarını geri alır; Windows Terminal profilini, token durumunu, kayıtlı konumu
ve runtime dosyalarını siler. İkinci komut indirdiğiniz `.claude-token-star`
klasörünü de siler.

## Linux/macOS kurulumu

Ghostty 1.3+, Claude Code ve Python 3.10+ gerekir:

```sh
git clone https://github.com/0Alduin0/Claude-Code-Token-Star.git .claude-token-star
sh ./.claude-token-star/install.sh
```

Kaldırma ve indirilen klasörü temizleme:

```sh
sh ./.claude-token-star/uninstall.sh
rm -rf -- ./.claude-token-star
```

## Sorun olursa

```powershell
.\.claude-token-star\token-test.ps1 doctor
```

Overlay yalnızca kurulumda seçilen proje desteklenen IDE'nin ön plan
penceresindeyken görünür. Değerler ilk Claude yanıtından önce boşsa `--`
gösterilmesi normaldir.

## Lisans

MIT. Yıldız evrimi için [NASA Star Lifecycle](https://science.nasa.gov/mission/webb/star-lifecycle/),
quasar görsel dili için [NASA Active Galactic Nuclei](https://science.nasa.gov/mission/webb/science-overview/science-explainers/what-are-active-galactic-nuclei/)
kaynak alınmıştır.
