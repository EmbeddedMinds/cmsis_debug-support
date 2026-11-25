# CMSIS Debugger entegrasyonu: CMake + pyOCD + özel FLM

Bu paket, CMake/GCC ile derlenen bir projeyi VS Code'da **Arm CMSIS Debugger** eklentisiyle debug edebilmeniz için gereken dosyaları üretir. GDB sunucusu olarak pyOCD kullanılır. pyOCD bağlı probe'u kendisi bulduğu için **ST-Link, J-Link ve CMSIS-DAP** probe'larında ayrıca ayar yapmanız gerekmez. Özel `.FLM` flash algoritmaları da üçünde aynı şekilde çalışır.

Paket yalnızca bir CMake dosyası ve şablonlardan oluşur. VS Code eklentileri, cihazın DFP pack dosyası ve özel FLM dosyaları pakete dahil değildir; bunları kendi araç zincirinizle kurup sağlarsınız. Python, Kconfig veya CMSIS-Toolbox gerekmez; pyOCD ve GDB, Arm CMSIS Debugger eklentisiyle birlikte gelir.

## 1. Nasıl çalışır?

CMake configure sırasında `cmsis_debug_init` fonksiyonu çalışır ve şablonlardan üç dosya üretir:

```text
CMakeLists.txt: cmsis_debug_init(...)
        |
        v
debugger/cmsis_debug.cmake --configure_file--> .vscode/launch.json
                                              <build>/debug/pyocd.yaml
                                              <build>/debug/pyocd_user_script.py
```

| Dosya | Görevi |
| --- | --- |
| `.vscode/launch.json` | VS Code'daki debug konfigürasyonları (launch ve iki attach). pyOCD'yi başlatır, GDB komutlarını içerir |
| `pyocd.yaml` | pyOCD ayarları: hedef cihaz, pack dosyası, SWD hızı, bağlanma şekli, smart flash, SWV |
| `pyocd_user_script.py` | pyOCD bağlanırken çalışır; özel FLM'leri ve isteğe bağlı RAM bölgelerini bellek haritasına ekler |

F5'e bastığınızda VS Code pyOCD'yi gdbserver olarak başlatır. pyOCD, cihazın bellek haritasını ve dahili flash algoritmasını pack dosyasından (pack verilmemişse kendi yerleşik hedef tanımından) alır, ardından user script'i çalıştırır. Son olarak GDB bağlanır ve `launch.json`'daki `initCommands` komutlarını sırayla çalıştırır.

Proje yerleşimi:

```text
<workspace>/                 VS Code'da açtığınız dizin
|- CMakeLists.txt
|- .vscode/launch.json       Üretilir
'- debugger/                 Bu paket
   |- cmsis_debug.cmake      Argümanları doğrular, dosyaları üretir
   '- templates/             launch.json, pyocd.yaml ve user script şablonları
```

## 2. Gereksinimler

- Windows x64, **VS Code 1.109+**, `PATH`'te `code` komutu
- **CMake 3.10+**
- **VS Code eklentileri** kurulu olmalı (Adım 2)
- Cihazın **DFP pack dosyası** (`.pack`). Hedef pyOCD'de yerleşikse gerekmez (`PACK_FILE` açıklamasına bakın)
- Harici flash'a yazacaksanız onun **özel FLM dosyaları** (`FLM_FILES`)
- **ASCII yollar:** Pack, FLM ve build dizininin yolunda Türkçe karakter olmamalı
- J-Link için SEGGER J-Link Software Pack
- ST-Link için USB sürücüsü ve en az **V2J32 / V3J2** firmware
- Keil **ULINKpro** desteklenmez: CMSIS-DAP değil, Keil'e özel bir protokol kullanır ve pyOCD onu görmez. **ULINKplus** ise CMSIS-DAP uyumludur ve çalışır.

## 3. Entegrasyon

### Adım 1: Paketi kopyalayın

Bu dizini `<workspace>/debugger/` olarak kopyalayın.

### Adım 2: Eklentilerin kurulu olduğunu kontrol edin

Eklentiler pakete dahil değildir, kendi araç zincirinizle kurun. Kurulu olduklarını şöyle kontrol edebilirsiniz:

```bat
code --list-extensions --show-versions
```

Listede en az `arm.vscode-cmsis-debugger` ve `eclipse-cdt.cdt-gdb-vscode` görünmeli. Paket, aşağıdaki tabloda yazan sürümlerle denendi.

#### Hangi eklenti ne işe yarar?

Arm CMSIS Debugger bir eklenti paketidir (extension pack): Kendi araçlarının yanında dört eklentiyi daha bağımlılık olarak getirir. Debug için **kesinlikle gereken iki eklenti** var, diğerleri ek görünümler sağlar:

| Eklenti | Sürüm | Gerekli mi? | Ne sağlar? |
| --- | --- | --- | --- |
| Arm CMSIS Debugger (`arm.vscode-cmsis-debugger`) | 1.10.1 | **Evet** | **pyOCD** (0.46.1) ve **GDB** (`arm-none-eabi-gdb` 15.3.1) bu eklentinin içinden gelir (`tools/pyocd`, `tools/gdb`). `launch.json`'daki `"server": "pyocd"` ve `"gdb": "arm-none-eabi-gdb"` değerlerini bu araçlara çözer. Ayrıca pyOCD veya GDB kurmanız gerekmez |
| CDT GDB Debug Adapter (`eclipse-cdt.cdt-gdb-vscode`) | 2.9.1 | **Evet** | `launch.json`'daki `"type": "gdbtarget"` debug türü bu eklentiden gelir. VS Code ile GDB arasındaki köprüdür: pyOCD'yi başlatır, GDB'yi bağlar, `initCommands`'ı çalıştırır, breakpoint ve adım adım ilerlemeyi yönetir |
| Peripheral Inspector (`eclipse-cdt.peripheral-inspector`) | 1.11.0 | `SVD_FILE` kullanıyorsanız | Debug sırasında çevre birimi register'larını gösteren görünüm. `launch.json`'daki `definitionPath` (SVD dosyası) bu eklenti tarafından okunur |
| Memory Inspector (`eclipse-cdt.memory-inspector`) | 1.3.0 | Hayır | Belleği hex olarak gösteren ve düzenlemeye izin veren görünüm |
| Serial Monitor (`ms-vscode.vscode-serial-monitor`) | 0.13.251128001 | Hayır | Seri port (UART) terminali. Debug ile ilgisi yoktur |

Gerekli olmayan eklentileri kullanmıyorsanız VS Code'da devre dışı bırakabilirsiniz, ama kurulumdan çıkarmayın: CMSIS Debugger kurulurken paketin üyelerini arar, bulamazsa internetten indirmeye çalışır. İnternetsiz kurulumda bu yüzden önce dört bağımlılığın `.vsix` dosyasını, en son CMSIS Debugger'ı kurun.

### Adım 3: SVD dosyasını çıkarın (isteğe bağlı)

Peripheral görünümünü kullanmak istiyorsanız ve araç zinciriniz SVD dosyasını ayrıca sağlamıyorsa, onu pack'ten bir kez çıkarın. `.pack` aslında bir zip dosyasıdır. Git ile gelen `tar` bunu açamaz, bu yüzden Windows'un kendi `tar.exe` aracını tam yoluyla çağırın. Pack ve hedef dizin yollarını kendi kurulumunuza göre değiştirin:

```bat
mkdir C:\tools\svd
%SystemRoot%\System32\tar.exe -xf C:\tools\packs\Keil.STM32H7RSxx_DFP.1.1.0.pack -C C:\tools\svd --strip-components 2 CMSIS/SVD/STM32H7S.svd
```

Dosya `C:\tools\svd\STM32H7S.svd` olarak oluşur. SVD'nin pack içindeki yolu, pack'teki `.pdsc` dosyasının `<debug svd=...>` satırında yazar (Bölüm 6).

### Adım 4: CMake'e bağlayın

Ana `CMakeLists.txt` dosyasına paketi ekleyip `cmsis_debug_init` fonksiyonunu çağırın. Örneklerdeki `C:/tools/...` yolları, araç zincirinizin pack, SVD ve FLM dosyalarını koyduğu yeri temsil eder. Aşağıdaki örnekte bütün argümanlar yazılı; yalnızca `TARGET_DEVICE` ve `PROGRAM_ELF` zorunlu. Yazmadığınız argümanlar için tablodaki varsayılan kullanılır.

```cmake
include("${CMAKE_SOURCE_DIR}/debugger/cmsis_debug.cmake")
cmsis_debug_init(
    TARGET_DEVICE  stm32h7s3l8hx
    PACK_FILE      C:/tools/packs/Keil.STM32H7RSxx_DFP.1.1.0.pack
    PROGRAM_ELF    build/out/App.elf
    LOAD_FILE      build/out/App_signed.hex
    SVD_FILE       C:/tools/svd/STM32H7S.svd
    FLM_FILES      C:/tools/flash/xspi1_nor.flm C:/tools/flash/xspi2_nor.flm
    FLM_RAM_START  0x20000000
    FLM_RAM_SIZE   0xF000
    FLM_PAGE_SIZE  0x1000
    SMART_FLASH    ON
    SWV_SYSTEM_CLOCK 600000000
    SWV_CLOCK      2000000
    DEBUGGER_FREQUENCY 8000000
    CONNECT_MODE   under-reset
    WORKSPACE_ROOT ${CMAKE_SOURCE_DIR}
)
```

Bilmeniz gereken birkaç kural:

- Yanlış yazılmış bir argüman adı configure'ı durdurur.
- Değeri boş olan argüman hiç yazılmamış sayılır. Bu sayede Kconfig'ten veya kart dosyasından gelen değişkenleri `TARGET_DEVICE ${CONFIG_...}` gibi doğrudan aktarabilirsiniz.
- Boşluk içeren değerleri tırnak içine alın.
- Yollarda `\` kullanabilirsiniz, otomatik olarak `/` yapılır. Türkçe karakter kullanamazsınız.

**Yollar yazdığınız gibi kullanılır.** Paket hiçbir yolu mutlak yola çevirmez; `PACK_FILE`, `PROGRAM_ELF`, `LOAD_FILE`, `SVD_FILE` ve `FLM_FILES` üretilen dosyalara aynen girer. Göreli yollar debug sırasında **workspace köküne** göre çözülür. Bunun sebebi GDB'nin ve pyOCD'nin `cwd: ${workspaceFolder}` ile başlatılması ve peripheral görünümünün de göreli SVD yolunu workspace köküne eklemesidir (üç eklentinin kaynak kodundan doğrulandı). Build dizinindeki bir ELF için yolu workspace kökünden yazın, örneğin `build/out/App.elf`. İsterseniz `${CMAKE_BINARY_DIR}/out/App.elf` gibi mutlak bir yol da verebilirsiniz.

#### `cmsis_debug_init` argümanları

| Argüman | Zorunlu | Değer | Varsayılan |
| --- | --- | --- | --- |
| `TARGET_DEVICE` | evet | pyOCD'nin hedef adı: DFP'deki cihaz adının küçük harfli yazımı. Örnek `stm32h7s3l8hx` | - |
| `PACK_FILE` | hayır | Cihazın DFP dosyası (`.pack`). Workspace dışında da olabilir (mutlak veya `../` ile göreli yol). Yalnızca hedef pyOCD'de yerleşikse atlanabilir, aşağıya bakın. Bulunamazsa configure uyarı verir | yok, pyOCD'nin yerleşik hedefi |
| `PROGRAM_ELF` | evet | Debug edilecek ELF; semboller buradan okunur. Build çıktısı olduğu için varlığına bakılmaz | - |
| `LOAD_FILE` | hayır | `launch` sırasında flash'a yazılacak dosya: `.hex`, `.srec` veya `.elf`. Adres bilgisi olmayan `.bin` olmaz. Varlığına bakılmaz. Yolda boşluk olamaz | `PROGRAM_ELF` |
| `SVD_FILE` | hayır | Peripheral görünümü için SVD dosyası (Adım 3). Workspace dışında da olabilir: mutlak yol (`D:/svd/STM32H7S.svd`) veya `../` ile göreli yol verin. Bulunamazsa uyarı verir | yok, görünüm kapalı |
| `FLM_FILES` | hayır | Bir veya birden fazla özel FLM dosyası, boşlukla ayrılmış. Bulunamazsa uyarı verir | yok |
| `FLM_RAM_START` | hayır | FLM'lerin çalışacağı RAM'in adresi, hex (`0x...`) veya ondalık. `FLM_RAM_SIZE` ile birlikte verilir | DFP'nin varsayılan RAM'i (H7S3: DTCM `0x20000000`, 64 KB) |
| `FLM_RAM_SIZE` | hayır | O RAM'in boyutu (bayt), hex veya ondalık. DFP haritasındaki RAM'i aşarsa pyOCD sınıra kırpar ve uyarır | DFP'nin varsayılan RAM'i |
| `FLM_PAGE_SIZE` | hayır | `ProgramPage`'e tek seferde gönderilen bayt sayısı, hex veya ondalık. FLM'deki `szPage`'den büyük olamaz, her sektör boyutunu tam bölmeli | FLM'deki `szPage` |
| `SMART_FLASH` | hayır | `ON` veya `OFF` | `ON` |
| `RAM_REGIONS` | hayır | pyOCD bellek haritasına eklenecek RAM'ler. `<başlangıç>:<boyut>` listesi, hex veya ondalık. **Şu an gerekmez**, aşağıya bakın | yok |
| `SWV_SYSTEM_CLOCK` | hayır | Verilirse SWV açılır ve ITM port 0 çıktısı Debug Console'da görünür. SWO saatinin türetildiği çekirdek saati, Hz, ondalık. Aşağıya bakın | yok, SWV kapalı |
| `SWV_CLOCK` | hayır | SWO hızı, Hz, ondalık. Yalnızca `SWV_SYSTEM_CLOCK` ile birlikte verilir | `1000000` |
| `DEBUGGER_FREQUENCY` | hayır | Probe ile işlemci arasındaki SWD saati, Hz, ondalık. Üst sınırlar: ST-Link V2 `4000000`, V3 `24000000`, J-Link `50000000` | `4000000` |
| `CONNECT_MODE` | hayır | `halt`, `pre-reset` veya `under-reset` | `pre-reset` |
| `WORKSPACE_ROOT` | hayır | VS Code'da açılan dizin, mutlak yol. `.vscode/launch.json` buraya yazılır, "dosya bulunamadı" uyarıları da buna göre bakar. Yalnızca `CMakeLists.txt` workspace kökünde değilse verin | `CMAKE_SOURCE_DIR` |

Argümanlar hakkında ayrıntılar:

- **`PACK_FILE`**: pyOCD, bazı cihazların tanımını (bellek haritası ve dahili flash algoritması) yerleşik olarak içerir. Hedefiniz bunlardan biriyse pack vermeden de çalışır. Kontrol etmek için `"%PYOCD%" list --targets` çalıştırın (Adım 6'daki `PYOCD` değişkeni): Kaynak sütununda `builtin` yazan hedefler pack istemez, örneğin `stm32h743xx`. Listede olmayan cihazlar için pack zorunludur; **`stm32h7s3l8hx` yerleşik değildir**. Pack verilmezse `pyocd.yaml`'a `pack:` satırı hiç yazılmaz (boş değer yazılsaydı pyOCD `CMSIS-Pack '.' is missing a .pdsc file` hatasıyla dururdu). Mümkünse yine de pack verin: Pack, cihaza özel debug sequence'larını ve daha ayrıntılı bellek haritasını da getirir. SVD dosyası her durumda ayrıca verilir.
- **`LOAD_FILE`**: Bootloader imza kontrolü yapıyorsa ham ELF yerine imzalı dosyayı burada verin. ELF'teki adresler imzalı imajla aynı olduğu sürece semboller ve breakpoint'ler sorunsuz çalışır.
- **`FLM_RAM_START` / `FLM_RAM_SIZE`**: FLM, DFP'nin varsayılan RAM'ine sığmıyorsa kullanın (Bölüm 5). Keil µVision'daki FLM RAM ayarında kullandığınız değerleri verebilirsiniz. H7S3'te AXI SRAM için örnek: `0x24000000` ve `0x72000`.
- **`FLM_PAGE_SIZE`**: Keil ve J-Link büyük bir `szPage` değerini zaten küçük parçalara bölerek gönderir; bu argüman pyOCD'nin de aynısını yapmasını sağlar. Sayfa tamponu küçüldüğü için FLM daha küçük bir RAM'e sığar. Örnek: `0x1000`.
- **`SMART_FLASH`**: `ON` iken pyOCD yüklemeden önce flash'ı okuyup imajla karşılaştırır. **Yalnızca farklı olan sektörler** silinip yeniden yazılır, aynı olanlar atlanır. Okumak için FLM'yi `Init(adr, clk, fnc=3)` ile çağırır (başarısız olursa `fnc=1` ile); FLM bu çağrıda flash'ı memory-mapped moda almalıdır. FLM `Verify` fonksiyonunu dışa açıyorsa pyOCD normalde smart flash'ı sessizce kapatır. Paket bunu önlemek için `Verify` sembolünü pyOCD'ye vermez; pyOCD bu sembolü başka hiçbir yerde kullanmaz. `OFF` iken her yüklemede imajın kapladığı bütün sektörler silinip yazılır.
- **`CONNECT_MODE`**: pyOCD'nin `launch` sırasında hedefe nasıl bağlanacağını belirler. Attach konfigürasyonları bu değeri kullanmaz (Bölüm 4).
  - `halt`: reset atmadan çekirdeği durdurur.
  - `pre-reset`: bağlanmadan önce NRST ile donanım reset'i atar.
  - `under-reset`: NRST basılı tutulurken bağlanır. Açılır açılmaz debug'ı kapatan veya düşük güç moduna giren uygulamalarda gerekir.

  Son ikisi için NRST hattının probe'a bağlı olması gerekir.

#### Harici RAM (PSRAM/SDRAM): ayar gerekmez

pyOCD, cihazın bellek haritasını DFP'den alıp GDB'ye gönderir. DFP'de kartınızdaki harici PSRAM veya SDRAM yer almaz. GDB de normalde haritada olmayan adreslere hiç erişmez, bu yüzden oradaki değişkenler Watch'ta `Cannot access memory at address 0x7000...` hatası verir.

Bunu çözmek için üç debug konfigürasyonunun hepsi bağlanırken GDB'ye şu komutu gönderir:

```text
set mem inaccessible-by-default off
```

Bu komuttan sonra GDB haritada olmayan adresleri de hedeften okur. Sizin bir şey yapmanız gerekmez. Bilmeniz gerekenler:

- **Harici RAM'i yazılım başlatır.** XSPI/FMC init kodu çalışmadan o adresler okunamaz ve `Memory transfer fault` görürsünüz. Bu durumda değişkene, init kodu çalıştıktan sonra bakın.
- **Haritanın sağladığı koruma kalkar.** Watch'a geçersiz bir pointer eklerseniz veya üzerine gelirseniz GDB o adresi de okumaya çalışır. Hedef bu erişimde hata verir ve pyOCD bunu `Cannot access memory` olarak gösterir; çalışan program bundan etkilenmez.
- **`RAM_REGIONS` şu an kullanılmıyor.** Bölgeleri pyOCD haritasına açıkça eklemek için hazır bir argüman, ancak doğru adres ve boyutu CMake'e taşımak projede büyük bir değişiklik gerektiriyor. Bu yüzden şimdilik kullanılmıyor. İleride nasıl devreye alınacağı [Bölüm 10](#10-yapılacaklar)'da anlatılıyor.

#### ITM (SWV) çıktısı: Debug Console

Firmware'in ITM üzerinden yazdığı metni görmek için ayrı bir terminal açmanız gerekmez. `SWV_SYSTEM_CLOCK` verildiğinde pyOCD SWV'yi açar, ITM port 0'a yazılan baytları metne çevirip kendi çıktısına basar; CDT GDB Debug Adapter da pyOCD'nin çıktısını VS Code'un **Debug Console**'unda gösterir. Üç debug konfigürasyonunda da çalışır.

```cmake
cmsis_debug_init(
    ...
    SWV_SYSTEM_CLOCK 600000000   # firmware'in ayarladigi cekirdek saati (Hz)
    SWV_CLOCK        2000000)    # SWO hizi (Hz), varsayilan 1000000
```

Bilmeniz gerekenler:

- **Çekirdek saatini doğru verin.** pyOCD, SWO hız bölücüsünü `SWV_SYSTEM_CLOCK / SWV_CLOCK` ile hesaplar. Değer, firmware saat ayarını yaptıktan sonraki gerçek saat olmalıdır; yanlışsa Debug Console'da bozuk karakterler görürsünüz. Oran tam sayıya yakın olmalı: Gerçek hız istenenden %3'ten fazla saparsa pyOCD SWV'yi açmaz.
- **Firmware tarafı.** pyOCD ITM'i ve TPIU'yu bağlanırken kendisi ayarlar (pack trace ayarını kendi debug sequence'larıyla yapıyorsa onu kullanır). Firmware'de CMSIS'in `ITM_SendChar()` fonksiyonuyla yazın veya `printf` çıktısını ona yönlendirin. STM32'de SWO pininin (genelde PB3, AF0) trace çıkışı olarak kullanılabildiğinden emin olun; firmware pini başka bir işe atamamalıdır.
- **Yalnızca port 0 metne çevrilir.** Diğer ITM portları Debug Console'da görünmez.
- **Ham akış TCP 3443'te.** pyOCD çözülmemiş SWO akışını bu porttan da yayınlar. İçinde ITM paket başlıkları olduğu için Serial Monitor'ün TCP modunda okunabilir metin görmezsiniz; ancak SWO'yu çözebilen bir araçla kullanılabilir.
- **Probe SWO desteklemeli.** pyOCD'nin ST-Link, CMSIS-DAP ve J-Link sürücülerinde SWO desteği var, ancak probe'un kendisi de SWO pinine bağlı olmalıdır.
- **pyOCD SWV'yi açamazsa** debug yine başlar ve Debug Console'da `SWV not initalized: ...` ile başlayan bir uyarı görürsünüz (Bölüm 8).

#### Karta özel değerler kart dosyasına

Projenizde birden fazla kart varsa karta özel değerleri ana `CMakeLists.txt`'ye değil, kart dosyasına yazın. Kart dosyası, projenizde kart seçimine göre `include` edilen CMake dosyasıdır (aşağıda `boards/<kart>/board.cmake`). Böylece ana dosyada hiçbir adres, cihaz adı veya dosya yolu kalmaz.

| Dosya | İçerik |
| --- | --- |
| `boards/<kart>/board.cmake` (her kart için ayrı) | `BOARD_TARGET_DEVICE`, `BOARD_PACK_FILE`, `BOARD_SVD_FILE`, `BOARD_FLM_FILES`, `BOARD_FLM_RAM_START`, `BOARD_FLM_RAM_SIZE`, `BOARD_FLM_PAGE_SIZE`, `BOARD_CONNECT_MODE`, `BOARD_DEBUGGER_FREQUENCY`, `BOARD_SWV_SYSTEM_CLOCK`. Kartta olmayan bir şeyi (ör. özel FLM) hiç yazmayın |
| `CMakeLists.txt` (ortak) | Kart dosyasını ve paketi `include` eder, `cmsis_debug_init`'i çağırır. Uygulamaya ait olan `PROGRAM_ELF`, `LOAD_FILE` ve `SMART_FLASH` burada kalabilir |
| `debugger/` (ortak paket) | `cmsis_debug.cmake`, `templates/`. Bütün kartlarda aynıdır, düzenlenmez ve kart dizinine kopyalanmaz |
| Araç zincirinin dizini (örnekte `C:/tools/`) | DFP, SVD ve FLM dosyalarının kendisi. Hepsini araç zinciriniz sağlar. Hangi kartın hangisini kullandığını yalnızca `board.cmake` belirler |

```cmake
# boards/<kart>/board.cmake - yalnizca bu kartin bilgileri
set(BOARD_TARGET_DEVICE stm32h7s3l8hx)
set(BOARD_PACK_FILE     C:/tools/packs/Keil.STM32H7RSxx_DFP.1.1.0.pack)
set(BOARD_SVD_FILE      C:/tools/svd/STM32H7S.svd)
set(BOARD_FLM_FILES     C:/tools/flash/xspi1_nor.flm C:/tools/flash/xspi2_nor.flm)
set(BOARD_CONNECT_MODE  under-reset)
```

```cmake
# CMakeLists.txt - karttan bagimsiz
include("${CMAKE_SOURCE_DIR}/boards/${BOARD}/board.cmake")
include("${CMAKE_SOURCE_DIR}/debugger/cmsis_debug.cmake")
cmsis_debug_init(
    TARGET_DEVICE ${BOARD_TARGET_DEVICE}
    PACK_FILE     ${BOARD_PACK_FILE}
    PROGRAM_ELF   build/out/App.elf
    SVD_FILE      ${BOARD_SVD_FILE}
    FLM_FILES     ${BOARD_FLM_FILES}
    FLM_RAM_START ${BOARD_FLM_RAM_START}
    FLM_RAM_SIZE  ${BOARD_FLM_RAM_SIZE}
    FLM_PAGE_SIZE ${BOARD_FLM_PAGE_SIZE}
    CONNECT_MODE  ${BOARD_CONNECT_MODE}
    DEBUGGER_FREQUENCY ${BOARD_DEBUGGER_FREQUENCY}
    SWV_SYSTEM_CLOCK ${BOARD_SWV_SYSTEM_CLOCK})
```

Kart dosyasında tanımlamadığınız bir değişken boş olarak aktarılır ve argüman hiç yazılmamış sayılır; yani varsayılan değer kullanılır. Bu yüzden ana dosyada `if` yazmanız gerekmez. Değişken adları sadece örnek; projenizde zaten olan kart değişkenlerini (Kconfig'in `CONFIG_...` değişkenleri dahil) doğrudan kullanabilirsiniz.

### Adım 5: Dosyaları üretin ve kontrol edin

CMake configure ve build çalıştırın. `.vscode/launch.json` ve `<build>/debug/` altındaki dosyalar oluşmuş olmalı. İçlerinde `@` işaretleri arasında kalmış bir değişken adı görmemelisiniz.

`.vscode/launch.json` her configure'da yeniden yazılır. Mevcut `launch.json`'ın ilk satırında `cmsis_debug:generated` yoksa dosyanın elle yönetildiği varsayılır: üzerine yazılmaz, CMake uyarı verir ve üretilen kopya `<build>/debug/launch.json` içinde kalır.

### Adım 6: Donanımı kontrol edin

Tek probe bağlıyken workspace kökünden şunları çalıştırın. `build` yerine kendi build dizininizi yazın; eklenti farklı bir sürümse veya başka bir dizine kurulduysa `PYOCD` yolunu ona göre düzeltin:

```bat
set PYOCD=%USERPROFILE%\.vscode\extensions\arm.vscode-cmsis-debugger-1.10.1-win32-x64\tools\pyocd\pyocd.exe

"%PYOCD%" list
"%PYOCD%" commander --config build\debug\pyocd.yaml -c "show map"
"%PYOCD%" load --config build\debug\pyocd.yaml build\App.elf
```

Beklenen sonuç: probe listelenir, `show map` çıktısında her FLM için o FLM'nin adını taşıyan bir `Flash` satırı görünür ve imaj hatasız yazılır.

### Adım 7: Debug'ı başlatın

Önce projeyi derleyin. VS Code'u `<workspace>` dizininde açın, **Run and Debug** görünümünden bir konfigürasyon seçip F5'e basın.

## 4. Debug konfigürasyonları

| Konfigürasyon | Ne yapar? |
| --- | --- |
| `<cihaz> launch (pyOCD)` | Reset atar, imajı yükler, tekrar reset atar ve `main`'in başında durur |
| `<cihaz> attach (to-running) (pyOCD)` | Yükleme ve reset yapmaz. Çekirdeği durdurmadan bağlanır, program çalışmaya devam eder (`-O connect_mode=attach`) |
| `<cihaz> attach (halt) (pyOCD)` | Yükleme ve reset yapmaz. Bağlanırken çekirdeği o an bulunduğu yerde durdurur (`-O connect_mode=halt`, `"run": "preserve"`) |

Üç konfigürasyon da bağlandıktan sonra ilk iş olarak `set mem inaccessible-by-default off` komutunu gönderir (bkz. [Harici RAM](#harici-ram-psramsdram-ayar-gerekmez)).

- **Attach konfigürasyonlarında bilerek `"request": "launch"` kullanılıyor.** VS Code'un debug adapter'ı (cdt-gdb-adapter, `gdbtarget`) pyOCD'yi yalnızca `launch` isteğinde başlatır. `attach` isteği ise önceden çalışan bir gdbserver'a bağlanmaya çalışır. Yükleme ve reset yapılmamasının sebebi, `initCommands` içinde `load` ve `reset` komutlarının olmamasıdır. Çekirdeğin durup durmayacağını ise pyOCD'ye verilen `connect_mode` belirler. Komut satırındaki `-O connect_mode=...`, `CONNECT_MODE` argümanıyla `pyocd.yaml`'a yazılan değeri ezer.
- **`"run": "preserve"` (attach halt):** Adapter, breakpoint yerleştirmek için hedefi durdurduysa varsayılan olarak (`"run": "all"`) sonunda programı devam ettirir. `preserve` bunu engeller ve çekirdek durduğu yerde kalır.
- **Probe seçimi:** Ayar yok, pyOCD bağlı olan tek probe'u kendisi seçer. **Aynı anda yalnızca bir probe bağlı olmalı.** Birden fazla probe varsa pyOCD konsoldan seçim yapmanızı bekler ve debug 30 saniye sonra zaman aşımına düşer. Hiç probe yoksa pyOCD beklemeden hata verir (`--no-wait`).
- **Yüklenen imaj:** Yalnızca `LOAD_FILE` (verilmemişse `PROGRAM_ELF`) yüklenir. Bootloader gibi başka imajları bir kez ayrıca yazın: `"%PYOCD%" load --config build\debug\pyocd.yaml <dosya>`
- **Yüklemeden sonraki reset:** Uygulama harici flash'ta (XSPI) çalışıyorsa bu belleği önce dahili flash'taki boot kodu açar. Boot kodunun flash'ta hazır olması gerekir.
- **Breakpoint'lerin hepsi donanımsal** (`soft_bkpt_as_hard`): Boot kodu uygulamayı RAM'e kopyalarsa yazılımsal breakpoint'ler silinir, donanımsal olanlar kalır. Aynı anda kullanabileceğiniz breakpoint sayısı çekirdeğin FPB birimiyle sınırlıdır (Cortex-M7'de 8).

## 5. FLM kuralları

- Adres aralığı ve sektör yapısı **FLM dosyasının içinden** okunur, ayrıca adres girmezsiniz.
- FLM'nin adres aralığı DFP'nin bellek haritasıyla çakışmamalı. Dahili flash için özel FLM vermeyin; DFP'deki algoritma kullanılır.
- **FLM'nin RAM'i:** FLM varsayılan olarak DFP'nin varsayılan RAM'inde çalışır (H7S3'te DTCM, `0x20000000`, 64 KB). Aşağıdaki toplamın bu RAM'e sığması gerekir:

  ```text
  4 bayt başlık + FLM'nin kod, data ve bss'i + szPage (sayfa tamponu) + en az 64 bayt stack
  ```

  Yer artarsa pyOCD ikinci bir sayfa tamponu açar (double buffering). Boyutları şöyle görebilirsiniz: `arm-none-eabi-size <dosya>.FLM`, `szPage` için `arm-none-eabi-gdb -batch -ex "p/x FlashDevice" <dosya>.FLM`.
- **FLM sığmıyorsa** sırasıyla şunları deneyin:
  1. FLM'yi küçültün: `szPage` değerini flash'ın programlama sayfasına (NOR için 256 bayt) indirin, büyük statik tamponları kaldırın.
  2. FLM'yi değiştiremiyorsanız `FLM_PAGE_SIZE` verin (örnek `0x1000`). Tampon küçülür ve FLM, Keil/J-Link'te çalıştığı DTCM'e sığar.
  3. Bu da yetmezse `FLM_RAM_START` / `FLM_RAM_SIZE` ile daha büyük bir RAM verin. H7S3'te AXI SRAM `0x24000000`'dan başlar ve option byte'larda `ECC_ON_SRAM=0` iken `0x72000` (456 KB) büyüklüğündedir; ECC açıksa boyut küçülür, reference manual'dan kontrol edin. Dikkat: AXI SRAM DTCM'in aksine önbelleğe alınabilen (cacheable) bir bölgedir. FLM'niz `Init` içinde D-cache açıyorsa sayfa tamponu yanlış okunabilir. Verdiğiniz RAM, DFP haritasındaki RAM bölgesini aşarsa pyOCD onu sınıra kırpar ve uyarı verir.
- **Smart flash** (`SMART_FLASH ON`, varsayılan): Değişmeyen sektörler atlanır; bir sektörde tek bir sayfa bile farklıysa o sektörün tamamı silinip yazılır.
  - **FLM'den beklenen:** pyOCD karşılaştırmayı FLM'nin `Verify` fonksiyonuyla değil, flash'ı **debugger üzerinden memory-mapped olarak okuyarak** yapar (başka yolu yok; FLM'lerde CRC fonksiyonu tanımlı değildir). Bu yüzden FLM, `Init(adr, clk, fnc=3)` çağrısında XSPI'ı memory-mapped moda alıp **öyle bırakmalı**, `UnInit(fnc=3)` çağrısında kapatmalıdır. pyOCD'nin çağırma sırası: `Init(3)` -> sayfaları oku -> `UnInit(3)` -> `Init(1)` -> sil -> `UnInit(1)` -> `Init(2)` -> yaz.
  - Memory-mapped modu yalnızca `Verify`/`BlankCheck` içinde açıp kapatan bir FLM (J-Link ve STM32CubeProgrammer için bu yeterlidir) pyOCD'de `Memory transfer fault (read) @ 0x90000000` hatası verir. FLM'yi düzeltene kadar `SMART_FLASH OFF` kullanın.
  - Çalışıp çalışmadığını yükleme logundaki `Erased N bytes ..., programmed M bytes, identical K bytes` satırından anlarsınız: Aynı imajı ikinci kez yüklediğinizde `identical` değeri imaj boyutuna yaklaşmalı ve yükleme kısalmalı.

## 6. Yeni işlemci ekleme

1. Hedef pyOCD'de yerleşikse (`list --targets` çıktısında `builtin`) pack olmadan da çalışır, yine de pack önerilir. DFP dosyasını araç zincirinize ekleyin (pack'ler `https://www.keil.com/pack/<Vendor>.<Pack>.<sürüm>.pack` adresinden indirilebilir) ve yolunu `PACK_FILE` ile verin.
2. Cihaz adını ve SVD yolunu pack içindeki `.pdsc` dosyasında bulun: `<device Dname=...>` satırları cihaz adını verir (`TARGET_DEVICE` için küçük harfe çevirin), `<debug svd=...>` satırları SVD'nin pack içindeki yolunu verir. SVD'yi Adım 3'teki komutla çıkarın.
3. `cmsis_debug_init` argümanlarını güncelleyip Adım 5'ten devam edin.

Bu yapı **tek çekirdekli** hedefler için hazırlandı.

## 7. Yapılmaması gerekenler

- `configure_file` çağrılarından `@ONLY` seçeneğini kaldırmayın. Kaldırırsanız `launch.json`'daki `${workspaceFolder}` boş değere dönüşür.
- Üretilen dosyaları elle düzenlemeyin. Şablonu veya `cmsis_debug_init` argümanlarını değiştirin.
- `launch.json`'a `cmsis.cbuildRunFile` veya `${command:cmsis-csolution...}` eklemeyin.
- `pyocd.yaml.in` ve `pyocd_user_script.py.in` dosyalarına Türkçe karakter yazmayın. pyOCD bu dosyaları Windows'un sistem kodlamasıyla okur, CMake ise UTF-8 yazar; `Ş` ve `Ğ` gibi karakterler cp1254'te okuma hatasına yol açar.
- `launch.json.in`'in ilk satırını ASCII dışında bir karakterle değiştirmeyin. CMake o satırı okuyup dosyanın elle yönetilip yönetilmediğine karar verir.

## 8. Sorun giderme

| Belirti | Çözüm |
| --- | --- |
| `cmsis_debug_init: ... is required` | Zorunlu bir argüman yazılmamış veya değeri boş |
| `cmsis_debug_init: unknown argument(s)` | Argüman adı yanlış yazılmış ya da bir değer boşluk içeriyor (yolu tırnak içine alın) |
| `cmsis_debug_init: file not found ...` uyarısı | Dosya bu yolla workspace kökünde bulunamadı. Yol yanlışsa düzeltin; dosya build sırasında üretiliyorsa uyarıyı dikkate almayabilirsiniz |
| `path must contain only ASCII characters` | Dosyaları Türkçe karakter içermeyen bir yola taşıyın |
| `launch.json ... left unchanged` uyarısı | Mevcut `launch.json` elle yazılmış. Yedekleyip silin veya `<build>/debug/launch.json` ile kendiniz birleştirin |
| Debug başlamıyor, `gdbtarget` debug türü tanınmıyor | CDT GDB Debug Adapter (`eclipse-cdt.cdt-gdb-vscode`) kurulu değil veya devre dışı (Adım 2) |
| `pyocd list` boş dönüyor | Probe takılı değil, sürücüsü yok veya pyOCD'nin desteklediği bir probe değil. Keil ULINKpro CMSIS-DAP olmadığı için hiç listelenmez (Bölüm 2) |
| `No connected debug probes` | Probe takılı değil veya sürücüsü yok. `"%PYOCD%" list` ile kontrol edin |
| `Cannot connect, port number not specified or regex is incorrect` | pyOCD 30 saniye içinde başlayamadı. Debug Console'daki çıktıya bakın. En sık sebep birden fazla probe'un bağlı olması |
| Attach'te `To open a remote debug connection, you need to specify what serial device is attached to the remote system` | Konfigürasyonda `"request": "attach"` yazıyor: adapter pyOCD'yi başlatmaz ve GDB'ye adressiz `target remote` gönderir. Şablondaki gibi `"request": "launch"` kullanın (Bölüm 4) |
| `Target type ... not recognized` | `TARGET_DEVICE` yanlış, `PACK_FILE` bu cihazı içermiyor ya da pack verilmemiş ve hedef pyOCD'de yerleşik değil (`list --targets`'ta `builtin` değil) |
| `Failed to load flash algorithm ... not enough memory space to fit flash algorithm` (ardından `Load failed`) | FLM ve sayfa tamponu FLM'nin RAM'ine sığmıyor. Bölüm 5'e bakın: FLM'yi küçültün veya `FLM_PAGE_SIZE` / `FLM_RAM_START` / `FLM_RAM_SIZE` verin |
| Yükleme hatasız bitiyor ama harici flash `0` okunuyor, uygulama çalışmıyor | Önce içeriği bağımsız bir araçla (STM32CubeProgrammer, J-Link) okuyun: Reset sonrası XSPI memory-mapped modda değildir ve `0x90000000` debugger'dan `0` görünebilir. İçerik gerçekten yanlışsa FLM'yi Keil/J-Link'teki koşullarda çalıştırın: `FLM_RAM_START 0x20000000`, `FLM_RAM_SIZE 0xF000`, `FLM_PAGE_SIZE 0x1000` |
| Yükleme hatasız, flash içeriği doğru ama bootloader "invalid image" diyor | Yüklenen dosya imzasız ELF. İmzalı dosyayı `LOAD_FILE` ile verin |
| `load` hata veriyor, `Cannot access memory` | ELF'teki adres hiçbir FLM aralığına düşmüyor. `show map` çıktısıyla karşılaştırın |
| `load`'un başında bellek okuma hatası | FLM'nin `Init` fonksiyonu XSPI'ı memory-mapped moda almıyor |
| `Erasing...`'den sonra `Memory transfer fault (read) @ 0x90000000-0x9000001f`, `Error finishing flash operation` | Smart flash okuması başarısız: FLM `Init(fnc=3)`'ten 0 döndü ama XSPI memory-mapped modda değil (FLM bu modu yalnızca `Verify`/`BlankCheck` içinde açıyor). Ya FLM'yi `Init(3)`'te memory-mapped modu açıp bırakacak şekilde düzeltin (Bölüm 5) ya da `SMART_FLASH OFF` yapın |
| Her yükleme aynı uzun sürede bitiyor, logda `identical 0 bytes` | Smart flash karşılaştırması işe yaramıyor: FLM `Init(fnc=3)` çağrısında flash'ı memory-mapped moda almıyor (Bölüm 5). `serverParameters` listesine `-L pyocd.flash.flash.trace=debug` ekleyip `init(..., op=3)` çağrısını ve sonucunu inceleyin |
| Çok büyük bir imajda `load` zaman aşımına düşüyor | İmajı önce `pyocd load` ile yazın ve şablondan `load` satırını çıkarın |
| Watch'ta değişken boş, `p &myVar` `Cannot access memory at address 0x7000...` veriyor | Değişken DFP haritasında olmayan harici RAM'de. `launch.json`'da `set mem inaccessible-by-default off` satırının olduğunu kontrol edin; elle yönetilen eski bir `launch.json` kullanıyor olabilirsiniz. Satır varken hata devam ediyorsa harici RAM henüz başlatılmamıştır (`Memory transfer fault`): XSPI/FMC init kodu çalıştıktan sonra tekrar bakın |
| Bağlanamıyor | NRST bağlantısını kontrol edin, `DEBUGGER_FREQUENCY`'yi `1000000` yapın, `CONNECT_MODE` için `under-reset` deneyin |
| `Not a genuine ST Device` veya debug sequence hatası | Sorunu ayırmak için `pyocd.yaml.in` dosyasına geçici olarak `pack.debug_sequences.disabled_sequences: DebugDeviceUnlock` ekleyin |
| `main`'de durmuyor | Boot kodu eksik olabilir ya da başka bir imajı başlatıyor olabilir |
| Debug Console'da ITM çıktısı yok | `SWV_SYSTEM_CLOCK` verilmiş mi ve `pyocd.yaml`'da `enable_swv: true` var mı bakın. Debug başlarken Debug Console'da `SWV not initalized` uyarısını arayın: `does not support SWO` probe'un SWO desteklemediğini, `does not have TPIU component with SWO UART mode` hedefin SWO birimini pyOCD'nin bulamadığını, `Failed to set SWO clock rate` ise `SWV_SYSTEM_CLOCK / SWV_CLOCK` oranının tutmadığını gösterir. Uyarı yoksa firmware'in ITM port 0'a yazdığını ve SWO pinini kontrol edin |
| ITM çıktısı bozuk karakterler | `SWV_SYSTEM_CLOCK` gerçek çekirdek saatiyle aynı değil. Firmware'in saat ayarından sonraki değeri verin veya daha düşük bir `SWV_CLOCK` deneyin |
| Port 3333 kullanımda | Task Manager'da açık kalmış `pyocd.exe` sürecini kapatın |

## 9. Doğrulama durumu

Ayarlar, NUCLEO-H7S3L8 ve ST-Link üzerinde çalıştığı belgelenmiş olan `altar-sdk` kurulumuyla (Linux, pyOCD 0.46.0) karşılaştırıldı: `initCommands` aynı (bu paket ek olarak `set mem inaccessible-by-default off` gönderiyor), attach için `-O connect_mode=attach` kullanılıyor, probe UID verilmeden otomatik seçiliyor ve FLM user script ile ekleniyor.

Eklentinin (1.10.1) ve içindeki pyOCD 0.46.1'in kaynak kodundan doğrulananlar:

- `"server": "pyocd"` ve `"gdb": "arm-none-eabi-gdb"` eklentinin içindeki araçları gösterir.
- `gdbserver` parametresi zaten varsa tekrar eklenmez.
- Probe verilmediğinde tek probe otomatik seçilir; birden fazla probe varsa konsoldan seçim istenir.
- `FlashRegion` user script ortamında tanımlıdır ve `flm` parametresi olarak `PackFlashAlgo` kabul eder.
- RAM verilmeyen bir FLM bölgesi, DFP'deki varsayılan RAM'lerden adresi en düşük olanı kullanır (H7S3: DTCM, 64 KB). DFP'de `default="0"` olan algoritmalar yüklenmez.
- `FLM_RAM_*` değerleri bölgeye `_RAMstart` / `_RAMsize` olarak verilir. pyOCD, DFP'deki algoritmaların `RAMstart` / `RAMsize` değerlerini de aynı şekilde verir ve RAM'i aynı kodla seçer. Bu yol donanımda denenmedi.
- Smart flash, bölgenin `are_erased_sectors_readable` bayrağına bağlıdır. pyOCD FLM'yi yüklerken bu bayrağı `'Verify' not in symbols` olarak ayarlar ve `Verify` sembolünü başka hiçbir yerde kullanmaz. Okumadan önce `Init(adr, 0, 3)` çağrılır. `SMART_FLASH` donanımda denenmedi.

Windows'ta eklentinin kendi `pyocd.exe` dosyasıyla test edilenler:

- `stm32h7s3l8hx` hedefi `Keil.STM32H7RSxx_DFP.1.1.0.pack` içinde bulunuyor.
- Probe yokken `gdbserver --no-wait` 2 saniyede `No connected debug probes` hatasıyla çıkıyor.
- Pack workspace dışındayken (mutlak yol, `\` ile yazılmış yol, `../` ile göreli yol, boşluklu dizin, workspace'ten farklı sürücü) üretilen `pyocd.yaml` ile `list --targets` `stm32h7s3l8hx` hedefini pack'ten buluyor.
- Pack verilmeden üretilen `pyocd.yaml` ile yerleşik `stm32h743xx` hedefi listeleniyor, `stm32h7s3l8hx` listelenmiyor. `pack: ''` yazılsaydı pyOCD hata verip duruyordu; paket bu yüzden satırı hiç yazmıyor.
- SWV: pyOCD `enable_swv` açıksa ITM port 0 baytlarını kendi stdout'una yazıyor (`gdbserver` alt komutu, `SWVReader`); CDT GDB adapter 2.9.1, pyOCD'nin stdout'unu Debug Console'a `server` çıktısı olarak gönderiyor. `swv_system_clock` yoksa SWV açılmıyor, saat bölücüde %3 sapma sınırı var.
- SVD workspace dışındayken (aynı yol türleri, farklı sürücü hariç) `launch.json`'daki yol, Peripheral Inspector 1.11.0'ın yol çözme mantığıyla gerçek SVD dosyasına çözülüyor.

CMake 3.10.3 ve 3.31.6 (Ninja, arm-none-eabi-gcc 13.2) ile test edilenler:

- Bütün argümanları dolu bir `cmsis_debug_init` çağrısı configure'dan hatasız geçiyor. Üretilen `launch.json` geçerli JSON, user script geçerli Python; dosyalarda `@...@` kalmıyor.
- Üretilen `launch.json`'daki üç konfigürasyonun hepsinde `set mem inaccessible-by-default off` var; launch'ta ilk komut olarak, attach'larda tek komut olarak.
- Karta özel değerleri kart dosyasından alan yapı: Bütün değerleri tanımlayan kart doğru dosyaları üretiyor, yalnızca cihaz adı ve pack tanımlayan kart hatasız geçiyor ve varsayılanları kullanıyor.
- `RAM_REGIONS` (şu an kullanılmıyor ama hazır): Üretilen user script, pyOCD 0.46.1'in bellek haritası sınıfıyla çalıştırıldığında bölgeleri ekliyor, varsayılan RAM'i değiştirmiyor. Boş, tanımsız ve tırnaklı değişken, `list(APPEND)` ile birden fazla bölge, hex/ondalık karışımı denendi. 20 farklı hatalı biçim configure'da; örtüşme, aynı bölgenin iki kez verilmesi ve 4 GB aşımı bağlanırken yakalanıyor.

**Test edilmedi:** Bu paketle gerçek donanım (üç probe türü de), VS Code içinde baştan sona debug, harici RAM'deki değişkenlerin `set mem inaccessible-by-default off` ile okunması, ITM çıktısının Debug Console'da görünmesi (özellikle STM32H7 ailesinde SWO'nun ayrı bir birimden çıkması nedeniyle pyOCD'nin bu birimi bulup bulamadığı).

## 10. Yapılacaklar

### Harici RAM bölgelerini CMake'ten tanımlamak (`RAM_REGIONS`)

**Şu anki durum:** Harici RAM'deki değişkenler, GDB'ye gönderilen `set mem inaccessible-by-default off` komutu sayesinde okunuyor. Bu ayar GDB'nin bellek haritası korumasını tamamen kapatıyor. Paket `RAM_REGIONS` argümanını ve user script tarafını zaten destekliyor (biçim kontrolü, örtüşme ve 4 GB kontrolü dahil, testli). Eksik olan şey, harici RAM'in adres ve boyutunun projede CMake'in okuyabileceği tek bir yerde tanımlı olması. Bu bilgi bugün yalnızca C başlık dosyalarında ve linker script'te bulunuyor.

**Ne zaman:** Proje, bellek tanımlarını (PSRAM/SDRAM başlangıç adresi ve boyutu) CMake'te üretmeye başladığında. Örneğin linker script'i ve C tanımlarını kart dosyasındaki CMake değişkenlerinden üreten bir yapı geldiğinde.

**Yapılacaklar:**

1. **Bellek tanımlarını tek kaynağa taşıyın.** Kart dosyasında harici RAM'ler için değişkenler tanımlayın, örneğin `BOARD_PSRAM_START` ve `BOARD_PSRAM_SIZE`. Linker script'i bu değişkenlerden `configure_file` ile üretin, C koduna `target_compile_definitions` ile verin. Böylece C kodu, linker script ve debugger aynı değeri kullanır ve birbirinden kopamaz.
2. **Kart dosyasında `RAM_REGIONS` listesini kurun.** Her harici RAM için bir satır yeter; ileride yeni bir RAM eklendiğinde bir satır daha eklenir:

   ```cmake
   list(APPEND BOARD_RAM_REGIONS ${BOARD_PSRAM_START}:${BOARD_PSRAM_SIZE})
   list(APPEND BOARD_RAM_REGIONS ${BOARD_SDRAM_START}:${BOARD_SDRAM_SIZE})
   ```

   - `string(APPEND)` kullanmayın, elemanları birbirinden ayırmaz.
   - Değerler boşluk içermemeli, hex (`0x...`) veya ondalık olmalı. Baştaki sıfır kabul edilmez (`0700...` hata verir).
   - Boyut olarak RAM'in tamamını verin. Yalnızca değişkenlerin kapladığı alanı verirseniz pointer ile erişilen heap ve buffer'lar okunamaz.
   - Kartta harici RAM yoksa listeyi hiç tanımlamayın; boş liste geçerlidir ve bölge eklenmez.
3. **Ana `CMakeLists.txt`'de listeyi aktarın:** `cmsis_debug_init(... RAM_REGIONS ${BOARD_RAM_REGIONS})`.
4. **`set mem inaccessible-by-default off` satırını kaldırın.** `templates/launch.json.in` içindeki üç konfigürasyondan da çıkarın. Attach konfigürasyonlarında başka komut kalmayacağı için `initCommands` satırını tamamen silebilirsiniz. Satır kalırsa her şey yine çalışır ama haritanın sağladığı koruma devreye girmez. Bu ayarı projeden projeye seçilebilir yapmak isterseniz `cmsis_debug_init`'e `GDB_UNMAPPED_ACCESS ON|OFF` gibi bir argüman ekleyip şablonda bir yer tutucuyla kullanabilirsiniz.
5. **Belgeleri güncelleyin.** Bu readme'de "Harici RAM" bölümünü, argüman tablosundaki `RAM_REGIONS` satırını, kart dosyası tablosunu ve örneğini (`BOARD_RAM_REGIONS` eklenecek), Bölüm 4'teki `set mem` notunu ve sorun giderme tablosundaki Watch satırını değiştirin. `cmsis_debug.cmake` başındaki açıklamada ve `pyocd_user_script.py.in` içindeki `RAM_REGIONS` yorumunda "şu an gerekmez" notlarını kaldırın. Sorun giderme tablosuna şu satırı ekleyin: `RAM_REGIONS ... overlaps memory map region(s): ...` hatası, bölgenin DFP haritasındaki bir bölgeyle veya başka bir girdiyle çakıştığını gösterir (bitişik bölgeler çakışma sayılmaz).
6. **Donanımda doğrulayın:**
   - pyOCD `commander -c "show map"` çıktısında `RAM_REGION0`, `RAM_REGION1`, ... satırları görünmeli.
   - Harici RAM'deki bir değişken (`p &myVar`, Watch) okunmalı.
   - Haritada olmayan bir adres (ör. geçersiz pointer) GDB tarafında, hedefe gitmeden `Cannot access memory` vermeli.
   - FLM yükleme davranışı değişmemeli: `FLM_RAM_START` verilmediğinde FLM yine DFP'nin RAM'inde çalışmalı (eklenen bölgeler varsayılan RAM yapılmaz).
   - ELF'te harici RAM'e doğrudan yüklenen bir section varsa (VMA ve LMA aynı) GDB `load` sırasında oraya yazmaya çalışır. `NOLOAD`/`.bss` ve flash'tan kopyalanan `.data` etkilenmez; böyle bir section varsa linker script'te düzeltin.
