# =============================================================================
# cmsis_debug.cmake: VS Code'da Arm CMSIS Debugger + pyOCD ile debug altyapısı
# =============================================================================
#
# Bu dosya ne yapar?
#   Projenin CMakeLists.txt dosyasında bir kez cmsis_debug_init(...) çağrılır. Fonksiyon configure
#   sırasında çalışır ve debug için gereken üç dosyayı templates/ altındaki şablonlardan üretir:
#
#     .vscode/launch.json                 VS Code'un debug konfigürasyonları (launch, attach)
#     <build>/debug/pyocd.yaml            pyOCD ayarları: hedef, pack, SWD hızı, bağlanma şekli
#     <build>/debug/pyocd_user_script.py  pyOCD'nin bağlanırken çalıştırdığı script: özel FLM'leri
#                                         ve istenirse ek RAM bölgelerini bellek haritasına ekler
#
#   Build gerekmez; configure yeterlidir. Ayrıntılı anlatım ve sorun giderme: readme.md.
#
#   Pakete dahil olmayanlar: VS Code eklentileri (Arm CMSIS Debugger ve CDT GDB Debug Adapter zorunlu;
#   pyOCD ve GDB CMSIS Debugger'ın içinden gelir), cihazın DFP pack dosyası ve özel FLM dosyaları. Bunlar
#   projenin kendi araç zinciriyle kurulur; pack, SVD ve FLM yolları cmsis_debug_init'e argüman olarak verilir.
#
# Debug başlarken ne olur?
#   1. VS Code, launch.json'daki konfigürasyonla pyOCD'yi gdbserver olarak başlatır
#      (pyocd gdbserver --config <build>/debug/pyocd.yaml ...).
#   2. pyOCD, cihazın bellek haritasını ve dahili flash algoritmasını pack dosyasından (PACK_FILE) veya
#      pack verilmemişse kendi yerleşik hedef tanımından alır, ardından user script'i çalıştırır. Script, FLM_FILES'taki her FLM için haritaya bir flash bölgesi
#      ekler; adres ve boyutu FLM'nin içinden okur.
#   3. GDB pyOCD'ye bağlanır ve launch.json'daki initCommands komutlarını sırayla çalıştırır
#      (launch'ta: reset, flash'a yükleme, reset, main'e breakpoint).
#
# Hangi argüman nereye gider? (argümanların açıklaması aşağıda)
#   launch.json         : TARGET_DEVICE (konfigürasyon adı), PROGRAM_ELF, LOAD_FILE, SVD_FILE
#   pyocd.yaml          : TARGET_DEVICE, PACK_FILE, DEBUGGER_FREQUENCY, CONNECT_MODE, SMART_FLASH,
#                         SWV_SYSTEM_CLOCK, SWV_CLOCK
#   pyocd_user_script.py: FLM_FILES, FLM_RAM_START/SIZE, FLM_PAGE_SIZE, SMART_FLASH, RAM_REGIONS
#
# Şablonlardaki önemli sabit ayarlar (değiştirmek için şablonu düzenleyin):
#   launch.json.in
#     "request": "launch"       Attach konfigürasyonlarında da bilerek "launch" kullanılır. Adapter
#                               (cdt-gdb-adapter) pyOCD'yi yalnızca launch isteğinde başlatır; "attach"
#                               çalışan bir sunucu bekler ve "serial device" hatasıyla düşer.
#     -O connect_mode=...       Attach konfigürasyonlarında pyocd.yaml'daki CONNECT_MODE değerini ezer:
#                               to-running için attach (çekirdek durmaz), halt için halt.
#     "run": "preserve"         attach (halt) konfigürasyonunda çekirdek durduğu yerde kalsın diye.
#     set mem inaccessible-by-default off
#                               GDB'nin pyOCD haritasında olmayan adresleri de okumasını sağlar. DFP'de
#                               olmayan harici PSRAM/SDRAM'deki değişkenler bu sayede Watch'ta görünür.
#   pyocd.yaml.in
#     soft_bkpt_as_hard: true   Bütün breakpoint'ler donanımsaldır; boot kodu imajı RAM'e kopyalasa da
#                               silinmezler. Sayısı çekirdekle sınırlıdır (Cortex-M7: 8).
#     flash.timeout.*: 60       Harici flash'ta uzun süren silme işlemleri zaman aşımına düşmesin diye.
#
# Önemli kurallar:
#   - Yollar verildiği gibi yazılır, mutlak yola çevrilmez. Göreli yollar çalışma anında workspace
#     köküne göre çözülür, çünkü GDB, pyOCD ve peripheral görünümü ${workspaceFolder} dizininde çalışır.
#   - Yollarda yalnızca ASCII karakter olabilir. Windows'taki \ ayraçları otomatik olarak / yapılır.
#   - configure_file çağrılarındaki @ONLY kaldırılmamalı; yoksa launch.json'daki ${workspaceFolder}
#     CMake tarafından boş değere çevrilir.
#   - pyocd.yaml.in ve pyocd_user_script.py.in dosyalarına Türkçe karakter yazılmamalı: pyOCD bu
#     dosyaları Windows'un sistem kodlamasıyla okur.

if(CMAKE_VERSION VERSION_LESS 3.10)
    message(FATAL_ERROR "cmsis_debug: CMake 3.10 or newer is required.")
endif()
include_guard(GLOBAL)

# Fonksiyonun içinde CMAKE_CURRENT_LIST_DIR, fonksiyonu çağıran dosyanın dizinini verir.
# Bu yüzden şablon dizinini dosya include edilirken burada saklıyoruz.
set(_CMSIS_DEBUG_TEMPLATE_DIR "${CMAKE_CURRENT_LIST_DIR}/templates")

# -----------------------------------------------------------------------------
# cmsis_debug_init(<ARGÜMAN> <değer> ...)
# -----------------------------------------------------------------------------
# Bilinmeyen bir argüman adı hata verir. Boş değerli argüman hiç verilmemiş sayılır; bu sayede
# tanımsız olabilecek değişkenler (ör. kart dosyasından gelen ${BOARD_...}) doğrudan aktarılabilir,
# tanımsızsa varsayılan kullanılır. Boşluk içeren değerler tırnağa alınmalıdır.
#
# Zorunlu argümanlar:
#   TARGET_DEVICE  pyOCD'nin hedef adı: DFP'deki cihaz adının küçük harfli yazımı.
#                  Örnek: stm32h7s3l8hx
#   PROGRAM_ELF    Debug edilecek ELF. Semboller buradan okunur; LOAD_FILE verilmezse flash'a da bu yazılır.
#                  Örnek: build/out/App.elf
#
# İsteğe bağlı argümanlar:
#   PACK_FILE      Cihazın DFP dosyası (.pack). Bellek haritası, dahili flash algoritması ve debug
#                  sequence'ları buradan gelir. Workspace dışında da olabilir (mutlak veya ../ ile göreli).
#                  Yalnızca hedef pyOCD'de yerleşikse atlanabilir: "pyocd list --targets" çıktısında
#                  kaynağı "builtin" olan hedefler (ör. stm32h743xx). stm32h7s3l8hx yerleşik değildir,
#                  pack ister. Pack verilmezse pyocd.yaml'a pack satırı hiç yazılmaz.
#                  Örnek: C:/tools/packs/Keil.STM32H7RSxx_DFP.1.1.0.pack
#                  Varsayılan: yok (pyOCD'nin yerleşik hedefi)
#   LOAD_FILE      launch sırasında flash'a yazılacak dosya: .hex, .srec veya .elf (adres bilgisi olmayan
#                  .bin olmaz). Bootloader imza kontrolü yapıyorsa imzalı dosyayı burada verin. Yolda
#                  boşluk olamaz, çünkü GDB'nin load komutu boşluklu yolu kabul etmez.
#                  Varsayılan: PROGRAM_ELF
#   SVD_FILE       Peripheral görünümü için SVD dosyası.
#                  Varsayılan: yok, görünüm kapalı
#   FLM_FILES      DFP'de olmayan flash'lar (ör. XSPI'a bağlı harici NOR) için özel FLM dosyaları,
#                  boşlukla ayrılmış. Adres ve sektör yapısı FLM'nin içinden okunur.
#                  Varsayılan: yok
#   FLM_RAM_START  FLM'lerin çalışacağı RAM'in adresi, hex (0x...) veya ondalık.
#   FLM_RAM_SIZE   O RAM'in boyutu (bayt), hex veya ondalık. İkisi birlikte verilir.
#                  FLM ve sayfa tamponu DFP'nin varsayılan RAM'ine sığmıyorsa kullanın.
#                  Varsayılan: DFP'nin varsayılan RAM'i (H7S3: DTCM, 0x20000000, 64 KB)
#   FLM_PAGE_SIZE  FLM'nin ProgramPage fonksiyonuna tek seferde gönderilen bayt sayısı. FLM'deki szPage
#                  değerinden büyük olamaz ve her sektör boyutunu tam bölmelidir. Küçük değer, sayfa
#                  tamponunu küçülttüğü için FLM'nin daha küçük RAM'e sığmasını sağlar (Keil ve J-Link
#                  de böyle yapar).
#                  Varsayılan: FLM'deki szPage
#   SMART_FLASH    ON | OFF. ON iken pyOCD yüklemeden önce flash'ı okuyup imajla karşılaştırır, yalnızca
#                  değişen sektörleri siler ve yazar. Bunun için FLM, Init(fnc=3) çağrısında flash'ı
#                  memory-mapped moda almalıdır; almıyorsa OFF yapın.
#                  Varsayılan: ON
#   RAM_REGIONS    pyOCD bellek haritasına eklenecek, DFP'de olmayan RAM'ler (harici PSRAM/SDRAM).
#                  <başlangıç>:<boyut> listesi, boşlukla ayrılmış veya CMake listesi, hex ya da ondalık.
#                  Örnek: 0x70000000:0x02000000
#                  Şu an gerekmez: launch.json'daki "set mem inaccessible-by-default off" sayesinde GDB
#                  haritada olmayan adresleri de okur. Bölgeleri açıkça tanımlamak isterseniz kullanın
#                  (readme.md, Yapılacaklar). Harici RAM'i yazılım başlatana kadar hiçbir yolla okunamaz.
#                  Varsayılan: yok
#   SWV_SYSTEM_CLOCK
#                  Verilirse SWV açılır: firmware'in ITM port 0'a yazdığı metin (ITM_SendChar, printf
#                  yönlendirmesi) VS Code'un Debug Console'unda görünür. Değer, SWO saatinin türetildiği
#                  çekirdek saatidir (Hz, ondalık); firmware'in saat ayarından sonraki gerçek değer
#                  olmalıdır, yanlışsa çıktı bozuk karakter olur. Probe'un SWO desteklemesi gerekir.
#                  Örnek: 600000000
#                  Varsayılan: yok, SWV kapalı
#   SWV_CLOCK      SWO hızı (Hz, ondalık). SWV_SYSTEM_CLOCK / SWV_CLOCK oranı tam sayıya yakın olmalı;
#                  pyOCD %3'ten fazla sapmada SWV'yi açmaz. Yalnızca SWV_SYSTEM_CLOCK ile birlikte geçerli.
#                  Varsayılan: 1000000
#   DEBUGGER_FREQUENCY
#                  Probe ile işlemci arasındaki SWD saati, Hz, ondalık. Bağlantı sorunlarında 1000000 deneyin.
#                  Sınırlar: ST-Link V2 4000000, V3 24000000, J-Link 50000000.
#                  Varsayılan: 4000000
#   CONNECT_MODE   pyOCD'nin hedefe nasıl bağlanacağı (launch için geçerlidir, attach konfigürasyonları
#                  kendi değerini kullanır):
#                    halt        reset atmadan çekirdeği durdurur
#                    pre-reset   bağlanmadan önce NRST ile donanım reset'i atar
#                    under-reset NRST basılıyken bağlanır; uygulama açılışta debug'ı kapatıyor veya uykuya
#                                giriyorsa gerekir
#                  Son ikisi için NRST probe'a bağlı olmalıdır.
#                  Varsayılan: pre-reset
#   WORKSPACE_ROOT VS Code'da açılan dizin, mutlak yol. .vscode/launch.json buraya yazılır, dosya var mı
#                  uyarıları da buna göre bakar. Yalnızca CMakeLists.txt workspace kökünde değilse verin.
#                  Varsayılan: CMAKE_SOURCE_DIR
#
# Örnek (bütün argümanlar):
#   cmsis_debug_init(
#       TARGET_DEVICE  stm32h7s3l8hx
#       PACK_FILE      C:/tools/packs/Keil.STM32H7RSxx_DFP.1.1.0.pack
#       PROGRAM_ELF    build/out/App.elf
#       LOAD_FILE      build/out/App_signed.hex
#       SVD_FILE       C:/tools/svd/STM32H7S.svd
#       FLM_FILES      C:/tools/flash/xspi1_nor.flm C:/tools/flash/xspi2_nor.flm
#       FLM_RAM_START  0x20000000
#       FLM_RAM_SIZE   0xF000
#       FLM_PAGE_SIZE  0x1000
#       SMART_FLASH    ON
#       RAM_REGIONS    0x70000000:0x02000000
#       SWV_SYSTEM_CLOCK 600000000
#       SWV_CLOCK      2000000
#       DEBUGGER_FREQUENCY 8000000
#       CONNECT_MODE   under-reset
#       WORKSPACE_ROOT ${CMAKE_SOURCE_DIR}
#   )
function(cmsis_debug_init)
    set(_one TARGET_DEVICE PACK_FILE PROGRAM_ELF LOAD_FILE SVD_FILE
             FLM_RAM_START FLM_RAM_SIZE FLM_PAGE_SIZE
             DEBUGGER_FREQUENCY CONNECT_MODE WORKSPACE_ROOT SMART_FLASH
             SWV_SYSTEM_CLOCK SWV_CLOCK)
    cmake_parse_arguments(ARG "" "${_one}" "FLM_FILES;RAM_REGIONS" ${ARGN})
    if(ARG_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "cmsis_debug_init: unknown argument(s): ${ARG_UNPARSED_ARGUMENTS}")
    endif()

    # --- Varsayılan değerler ve doğrulama ----------------------------------------
    if(NOT ARG_WORKSPACE_ROOT)
        set(ARG_WORKSPACE_ROOT "${CMAKE_SOURCE_DIR}")
    endif()
    if(NOT ARG_DEBUGGER_FREQUENCY)
        set(ARG_DEBUGGER_FREQUENCY 4000000)
    endif()
    if(NOT ARG_CONNECT_MODE)
        set(ARG_CONNECT_MODE "pre-reset")
    endif()
    if("${ARG_SMART_FLASH}" STREQUAL "")
        set(ARG_SMART_FLASH ON)
    endif()

    foreach(_var TARGET_DEVICE PROGRAM_ELF)
        if("${ARG_${_var}}" STREQUAL "")
            message(FATAL_ERROR "cmsis_debug_init: ${_var} is required.")
        endif()
    endforeach()
    if(NOT ARG_CONNECT_MODE MATCHES "^(halt|pre-reset|under-reset)$")
        message(FATAL_ERROR "cmsis_debug_init: CONNECT_MODE must be halt, pre-reset or under-reset.")
    endif()
    if(NOT ARG_DEBUGGER_FREQUENCY MATCHES "^[1-9][0-9]*$")
        message(FATAL_ERROR "cmsis_debug_init: DEBUGGER_FREQUENCY must be a decimal number in Hz.")
    endif()
    # SMART_FLASH iki dosyaya iki farklı yazımla gider: pyocd.yaml'a true/false, Python'a True/False.
    if(ARG_SMART_FLASH STREQUAL "ON")
        set(_dbg_smart_flash true)
        set(_dbg_smart_flash_py True)
    elseif(ARG_SMART_FLASH STREQUAL "OFF")
        set(_dbg_smart_flash false)
        set(_dbg_smart_flash_py False)
    else()
        message(FATAL_ERROR "cmsis_debug_init: SMART_FLASH must be ON or OFF.")
    endif()

    # SWV (ITM printf). SWV_SYSTEM_CLOCK verilmezse pyocd.yaml'a yalnızca yorum satırı yazılır.
    if(ARG_SWV_CLOCK AND NOT ARG_SWV_SYSTEM_CLOCK)
        message(FATAL_ERROR "cmsis_debug_init: SWV_CLOCK requires SWV_SYSTEM_CLOCK.")
    endif()
    if(ARG_SWV_SYSTEM_CLOCK)
        if(NOT ARG_SWV_CLOCK)
            set(ARG_SWV_CLOCK 1000000)
        endif()
        foreach(_var SWV_SYSTEM_CLOCK SWV_CLOCK)
            if(NOT "${ARG_${_var}}" MATCHES "^[1-9][0-9]*$")
                message(FATAL_ERROR "cmsis_debug_init: ${_var} must be a decimal number in Hz.")
            endif()
        endforeach()
        set(_dbg_swv_lines "enable_swv: true\nswv_system_clock: ${ARG_SWV_SYSTEM_CLOCK}\nswv_clock: ${ARG_SWV_CLOCK}")
    else()
        set(_dbg_swv_lines "# enable_swv: not set (SWV_SYSTEM_CLOCK)")
    endif()

    # Windows'ta yazılan \ ayraçlarını / yapıyoruz; JSON ve YAML'da \ kaçış karakteridir.
    foreach(_var WORKSPACE_ROOT PACK_FILE PROGRAM_ELF LOAD_FILE SVD_FILE FLM_FILES)
        file(TO_CMAKE_PATH "${ARG_${_var}}" ARG_${_var})
    endforeach()

    # --- Şablon değişkenleri -------------------------------------------------------
    # templates/*.in içindeki @_dbg_...@ yer tutucuları bu değişkenlerle doldurulur.
    # Yollar kullanıcının yazdığı gibi kalır, mutlak yola çevrilmez.
    set(_dbg_device       "${ARG_TARGET_DEVICE}")
    set(_dbg_frequency    "${ARG_DEBUGGER_FREQUENCY}")
    set(_dbg_connect_mode "${ARG_CONNECT_MODE}")
    set(_dbg_pack         "${ARG_PACK_FILE}")
    # pyocd.yaml'daki pack satırı. Boş değer yazılamaz: pyOCD "pack: ''" değerini "." dizini sanıp
    # "CMSIS-Pack '.' is missing a .pdsc file" hatasıyla durur. Pack yoksa satır yorum olarak kalır.
    if(ARG_PACK_FILE)
        set(_dbg_pack_line "pack: '${ARG_PACK_FILE}'")
    else()
        set(_dbg_pack_line "# pack: not set, TARGET_DEVICE must be a pyOCD builtin target")
    endif()
    set(_dbg_elf          "${ARG_PROGRAM_ELF}")
    set(_dbg_svd          "${ARG_SVD_FILE}")
    set(_dbg_flm_list     "${ARG_FLM_FILES}")

    # launch konfigürasyonundaki GDB load komutu. Tek başına "load", program olarak verilen ELF'i yazar.
    # LOAD_FILE verilirse (ör. imzalı hex) o dosya yazılır, ELF yalnızca semboller için kullanılır.
    set(_dbg_load_cmd "load")
    if(ARG_LOAD_FILE)
        if(ARG_LOAD_FILE MATCHES "[^!-~]")
            message(FATAL_ERROR "cmsis_debug_init: LOAD_FILE path must not contain spaces or non-ASCII characters: ${ARG_LOAD_FILE}")
        endif()
        set(_dbg_load_cmd "load ${ARG_LOAD_FILE}")
    endif()

    # FLM'lerin çalışacağı RAM. pyOCD bu değerleri flash bölgesinin _RAMstart/_RAMsize alanlarından okur.
    # Boş kalırsa pyOCD DFP'nin varsayılan RAM'ini kullanır.
    set(_dbg_flm_ram "")
    if(ARG_FLM_RAM_START OR ARG_FLM_RAM_SIZE)
        foreach(_var FLM_RAM_START FLM_RAM_SIZE)
            if(NOT "${ARG_${_var}}" MATCHES "^(0[xX][0-9A-Fa-f]+|[1-9][0-9]*)$")
                message(FATAL_ERROR "cmsis_debug_init: ${_var} must be a hex (0x...) or decimal number; "
                                    "FLM_RAM_START and FLM_RAM_SIZE are set together.")
            endif()
        endforeach()
        set(_dbg_flm_ram "'_RAMstart': ${ARG_FLM_RAM_START}, '_RAMsize': ${ARG_FLM_RAM_SIZE}")
    endif()

    # FLM'ye tek seferde gönderilen veri miktarı. 0, user script'te "FLM'deki szPage'i kullan" demektir.
    set(_dbg_flm_page 0)
    if(ARG_FLM_PAGE_SIZE)
        if(NOT "${ARG_FLM_PAGE_SIZE}" MATCHES "^(0[xX][0-9A-Fa-f]+|[1-9][0-9]*)$")
            message(FATAL_ERROR "cmsis_debug_init: FLM_PAGE_SIZE must be a hex (0x...) or decimal number.")
        endif()
        set(_dbg_flm_page "${ARG_FLM_PAGE_SIZE}")
    endif()

    # Ek RAM bölgeleri. Her "başlangıç:boyut" girdisi Python'da "(başlangıç, boyut), " olarak yazılır.
    # Biçim burada kontrol edilir; örtüşme ve 4 GB sınırını user script bağlanırken kontrol eder.
    # Düzenli ifade baştaki sıfırı reddeder (0700... sekizlik sanılmasın), boyut sıfır olamaz.
    set(_dbg_ram_regions "")
    foreach(_region IN LISTS ARG_RAM_REGIONS)
        if(NOT _region MATCHES "^(0[xX][0-9A-Fa-f]+|0|[1-9][0-9]*):(0[xX][0-9A-Fa-f]*[1-9A-Fa-f][0-9A-Fa-f]*|[1-9][0-9]*)$")
            message(FATAL_ERROR "cmsis_debug_init: RAM_REGIONS entries must be <start>:<size> "
                                "(hex 0x... or decimal, size > 0): ${_region}")
        endif()
        string(APPEND _dbg_ram_regions "(${CMAKE_MATCH_1}, ${CMAKE_MATCH_2}), ")
    endforeach()

    # Dosyalar workspace köküne göre aranır; bulunamazsa yalnızca uyarı verilir, yol değiştirilmez.
    # PROGRAM_ELF ve LOAD_FILE build çıktısı olduğu için configure sırasında henüz olmayabilir, bakılmaz.
    foreach(_file IN LISTS _dbg_pack _dbg_svd _dbg_flm_list)
        set(_probe "${_file}")
        if(NOT IS_ABSOLUTE "${_probe}")
            set(_probe "${ARG_WORKSPACE_ROOT}/${_probe}")
        endif()
        if(NOT EXISTS "${_probe}")
            message(WARNING "cmsis_debug_init: file not found (checked relative to WORKSPACE_ROOT): ${_file}")
        endif()
    endforeach()

    set(_dbg_out    "${CMAKE_BINARY_DIR}/debug")
    set(_dbg_yaml   "${_dbg_out}/pyocd.yaml")
    set(_dbg_script "${_dbg_out}/pyocd_user_script.py")

    # Bu yollar pyocd.yaml ve user script'e yazılır. CMake UTF-8 yazar, pyOCD ise sistem kodlamasıyla
    # (Türkçe Windows'ta cp1254) okur; ASCII dışı karakter yolu bozar.
    foreach(_path IN LISTS _dbg_pack _dbg_flm_list _dbg_script)
        if(_path MATCHES "[^ -~]")
            message(FATAL_ERROR "cmsis_debug_init: path must contain only ASCII characters: ${_path}")
        endif()
    endforeach()

    # --- Dosyaları üret ------------------------------------------------------------
    # @ONLY şart: yalnızca @...@ yer tutucuları doldurulur, launch.json'daki ${workspaceFolder}
    # VS Code'a olduğu gibi kalır.
    set(_tpl "${_CMSIS_DEBUG_TEMPLATE_DIR}")
    configure_file("${_tpl}/pyocd.yaml.in"           "${_dbg_yaml}"   @ONLY)
    configure_file("${_tpl}/pyocd_user_script.py.in" "${_dbg_script}" @ONLY)
    configure_file("${_tpl}/launch.json.in"          "${_dbg_out}/launch.json" @ONLY)

    # launch.json önce build dizinine üretilir, sonra .vscode'a kopyalanır. İlk satırında
    # "cmsis_debug:generated" olmayan bir launch.json elle yönetiliyor demektir; üzerine yazılmaz.
    set(_launch "${ARG_WORKSPACE_ROOT}/.vscode/launch.json")
    set(_head "cmsis_debug:generated")
    if(EXISTS "${_launch}")
        file(STRINGS "${_launch}" _head LIMIT_COUNT 1)
    endif()
    if(_head MATCHES "cmsis_debug:generated")
        configure_file("${_dbg_out}/launch.json" "${_launch}" COPYONLY)
    else()
        message(WARNING "cmsis_debug_init: ${_launch} is managed by hand, left unchanged. "
                        "Generated copy: ${_dbg_out}/launch.json")
    endif()
endfunction()
