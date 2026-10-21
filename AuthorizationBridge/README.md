# 20-20 AuthorizationBridge

Lokální podpisový backend pro **20-20 TOOLBOX → Autorizace PDF**.

## Verze 2.6.0 — kompletní lokální TEST B-LT

Pro bezplatný technický test zapněte **TEST**, **plně lokální TEST certifikát**
a **lokální TEST TSA**, poté zvolte profil **PAdES B-LT**.
Není potřeba Windows certifikát, USB token, PIN ani placená TSA.

Bridge vytvoří dočasnou testovací kořenovou a mezilehlou CA, podpisový
certifikát, TSA certifikát a podepsané OCSP/CRL. Po doplnění DSS znovu
ověří podpis i razítko offline pouze s testovací důvěrou. Pokud tato kontrola
selže, vrátí B-T s výslovným upozorněním, nikoli potvrzení B-LT.

ZIP obsahuje veřejný `TEST_ROOT_CA.pem` pro samostatné ověření testu.
Tento kořen neinstalujte do systémového úložiště důvěry. Soukromé klíče
zůstávají pouze v paměti; po restartu nebo obnově testovací PKI vzniknou jiné.
PKI se obnovuje po 12 hodinách. Nejde o kvalifikovaný podpis ani kvalifikované
časové razítko a veřejné validátory testovací kořen standardně neuznávají.
Windows certifikát s lokální TEST TSA nadále vyžaduje vlastní ověřitelné
revokační podklady; kompletní offline test proto používá plně lokální režim.
Shoda PDF/A se posuzuje samostatně validátorem finálního PDF.

## Verze 2.5.1 — opravy bezpečnosti exportu

- TEST podpisový certifikát smí i přes API používat pouze explicitně zvolenou
  lokální TEST TSA; tato kontrola proběhne před vytvořením externího TSA klienta.
- Všechny vstupní PDF a stránky podpisů se kontrolují před prvním podpisem
  a před otevřením Windows podpisové relace.
- Při pozdějším selhání dávky se vrátí již dokončené PDF v ZIPu spolu s
  `POZOR_DAVKA_NEDOKONCENA.txt`. Manifest rozlišuje `failed_files` a
  `unprocessed_files`; web označí nedokončené položky jako chybu. Zpracování
  se zastaví bez automatického opakování podpisů či dalších TSA požadavků.
  U selhané položky nelze obecně vyloučit již vydané razítko, proto neopakujte
  celou dávku bez kontroly výsledku.
- Adobe CMS přikládá pouze dostatečnou sadu revokační evidence ověřenou
  v nových offline validačních kontextech se stejnou politikou, časem a důvěrou.
  Poškozené a nepotřebné kandidátní OCSP/CRL se odstraní. Výsledek musí být
  znovu ověřitelný pouze s veřejnými certifikáty dostupnými ve výstupu.
- Oba frontendové regresní testy spustíte příkazy
  `node AuthorizationBridge/test_ui_signing_intent.cjs` a
  `node AuthorizationBridge/test_ui_partial_batch.cjs` z kořene repozitáře.

## Verze 2.5.0 — kompatibilní CMS export

Profil **PDF-XChange kompatibilní · CMS + OCSP/CRL (BETA)** vytváří
`adbe.pkcs7.detached`, přikládá ověřené revokační údaje podepisujícího
do podepsaného CMS a používá certifikační oprávnění DocMDP P=2.
Současný profil **PAdES B-LT** zůstává samostatný a výchozí.

- Vyžaduje Windows podpisový certifikát, sestavitelný CA řetězec a dostupné
  ověřitelné OCSP/CRL. Při jejich selhání se CMS Adobe nepodepíše.
- Na jedno PDF se vyžádá jedno podpisové RFC 3161 razítko; automatický
  odhad velikosti ani pomocný TSA požadavek se nepoužívá.
- Pro bezplatný test lze použít skutečný Windows certifikát s lokální TEST
  TSA. Takový výstup nemá kvalifikované razítko. Plně lokální TEST certifikát
  není v Adobe profilu povolen.
- Adobe režim přikládá podklady podpisového řetězce jako referenční
  PDF-XChange, nikoli úplné dlouhodobé podklady TSA. Neoznačuje se B-LT.
- Textový vzhled vkládá font Arial z Windows; v Linux testech DejaVu nebo
  Liberation Sans. Vyžaduje `pyHanko[opentype]`. Fontové soubory se
  nedistribuují. PNG/JPG vzhled zůstává podporován.
- Převod PDF/A probíhá před podpisem. Po podpisu ani po doplnění DSS se
  PDF Ghostscriptem nepřevádí. Již existující podpisy nezachovávejte tímto
  konverzním postupem; pro podepsané vstupy použijte samostatný workflow.
- Pokud je nainstalované veraPDF, ověří se konečný soubor v profilu 3b.
  Automatická kontrola má společný časový rozpočet 10 sekund na export
  (ukončení procesu může přidat několik sekund); její nedostupnost nebo
  timeout nezničí již podepsaný výstup. ZIP obsahuje `.validation.json`
  a manifest oddělující požadovaný standard od výsledku validace.
- QES/QTSA se při exportu automaticky netvrdí. Úplnou nezávislou kontrolu
  spusťte v **PDF Validatoru**; závisí na skutečném certifikátu, QSCD,
  poskytovateli a důvěryhodných seznamech.

Kompletní rozbalený instalační balíček lze spustit přes `INSTALL_AND_START.bat`:
instalátor použije přiložené soubory a ověří stejné SHA-256 jako při stahování.
Samostatně stažený BAT vyžaduje, aby připnutý payload commit již byl publikován
na GitHubu. Lokální změna ani lokální commit se samy nepublikují.

Regresní sada: `python -m unittest discover -s AuthorizationBridge -p 'test_*.py' -v`
z kořene repozitáře po instalaci `requirements.txt` a `pypdf>=5,<7`.
Testy používají vlastní dočasnou PKI a lokální razítka; není potřeba PIN ani
placená TSA. Windows QSCD, PDF-XChange/Acrobat a úplná shoda PDF/A se musí
ověřit také v cílovém Windows prostředí.

## Co dělá

- načte uživatelem vybraný PKCS#12 certifikát (`.pfx` / `.p12`) s privátním klíčem,
- vytváří podpisy **PAdES B-B** nebo **PAdES B-T**,
- pro B-T používá uživatelem zadaný **RFC 3161 TSA** server,
- umí viditelný podpisový widget na zvolené stránce a pozici,
- jako vzhled podpisu může použít PNG/JPG razítko,
- podepíše celý balík PDF a vrátí ZIP.

## Bezpečnost

Bridge naslouchá pouze na `127.0.0.1:8094`. PFX/P12, heslo ani PDF se neukládají do cloudu ani do repozitáře. PFX je v bridge zapsán jen do dočasného souboru nutného pro načtení knihovnou pyHanko a po načtení se ihned smaže. Heslo se neukládá.

## Instalace ve Windows

Z Toolboxu klikni **Instalátor** nebo spusť `INSTALL_AND_START.bat`. Instalátor:

1. vytvoří `%LOCALAPPDATA%\20-20-TOOLBOX\AuthorizationBridge`,
2. vytvoří izolované Python venv,
3. nainstaluje pyHanko + Flask + Pillow,
4. zaregistruje protokol `twentytwentyauth://`,
5. spustí lokální bridge.

Při dalších použitích stačí v Toolboxu **Spustit bridge**.

## Poznámka k platnosti podpisu

Aplikace vytvoří kryptografický PAdES podpis. To, zda jde současně o kvalifikovaný elektronický podpis podle eIDAS, závisí také na použitém certifikátu, privátním klíči / podpisovém prostředku a poskytovateli důvěryhodných služeb. Samotná aplikace kvalifikovaný status certifikátu nevytváří.


## PDF/A-3b workflow v1.1

Autorizace v Toolboxu používá stejný Ghostscript/WASM převod jako samostatný modul **Konverze do PDF/A**. Každý vstup se nejprve převede na **PDF/A-3b** a až poté se pošle lokálnímu bridge k PAdES podpisu. Toto pořadí je záměrné: převod přes Ghostscript po podpisu by kryptografický podpis zneplatnil.

Výstupní soubory mohou volitelně dostat suffix `_EAR.pdf`. Volba je řízená Toolboxem a bridge ji respektuje i na backendu; při zapnutém suffixu se `_EAR` nepřidá dvakrát.


## Security hardening v1.5

AuthorizationBridge stále naslouchá pouze na `127.0.0.1:8094`, ale navíc odmítá podpisové požadavky z neznámých webových originů. Povolený Toolbox si při otevření vyžádá náhodný in-memory session token a každý citlivý POST musí tento token poslat v hlavičce `X-20-20-Session`.

- wildcard CORS (`Access-Control-Allow-Origin: *`) byl odstraněn,
- session token se po restartu bridge vždy změní a neukládá se na disk,
- PFX/P12 a heslo se neposílají na GitHub ani jiný aplikační server,
- PFX se při načtení krátce zapíše do lokálního dočasného souboru a ihned se odstraní,
- při PAdES B-T komunikuje bridge s uživatelem zadaným TSA serverem; ten dostává timestamp request založený na kryptografickém otisku, nikoli privátní klíč.

## Rychlý batch export

Autorizace používá až dva samostatné Web Workery s Ghostscript WASM, takže na vhodném desktopu mohou běžet dva PDF/A-3b převody současně. Parametry převodu a ICC profil jsou stejné jako v původním převodu; nezavádí se nižší DPI ani rasterizační režim. Výsledný ZIP používá STORE místo zbytečné druhé komprese již komprimovaných PDF.


## Volitelný suffix _EAR v1.6

Toolbox obsahuje volbu **přidat _EAR za název exportovaného PDF**. Výchozí stav je zapnutý kvůli zpětné kompatibilitě. Po vypnutí bridge zachová běžný název PDF bez suffixu `_EAR`.


## USB/QSCD RSA oprava v2.1.9

U některých ovladačů USB tokenů může RSA privátní handle hlásit nepřesnou délku `KeySize`, přestože veřejný certifikát má např. RSA 4096 bitů. Dávkový podpis proto ověřuje sílu klíče podle veřejné části vybraného certifikátu (minimálně 2048 bitů) a po každém použití privátního klíče kryptograficky ověřuje vrácený podpis proti témuž certifikátu. PIN se nikde neukládá; úspěšné jednorázové ověření pro celou dávku závisí na tokenu a jeho ovladači.

Tato oprava **nemění** časová razítka: PAdES B-T používá jeden RFC 3161 podpisový timestamp na výstupní PDF a zachovává pevnou rezervaci podpisu bez dalšího odhadového TSA požadavku. Před ostrým podepisováním doporučujeme 8 PDF proti lokální TEST TSA, ověřit počítadlo 8/8 a počet PIN výzev. Ostrou spotřebu u poskytovatele tato lokální kontrola sama o sobě nepotvrzuje.


## Testovaná změna 2.3.1 – certifikační řetězec Windows

Při podepisování pomocí Windows Certificate Store se nyní volitelně načtou
veřejné certifikáty nadřazených CA z Windows X509Chain. Každé navázání
certifikátu se před vložením do CMS kryptograficky ověří. Veřejné certifikáty
mezilehlé a kořenové autority se předají do pyHanko cert_registry.

- Privátní klíč, PIN, implementace RSA podpisu a RFC 3161 TSA se **nemění**.
- Neprovádí se další žádost o placené časové razítko.
- Pokud Windows řetězec nedokáže sestavit, podpis se vytvoří původním postupem;
  do logu se vypíše diagnostika a ca_certificate_count je 0.
- Vložení CA certifikátů **nezakládá důvěryhodnost**: rozhodují pravidla
  a důvěryhodné seznamy validátoru.
- Tato změna **nepřidává OCSP/CRL ani PAdES-LT**. To vyžaduje samostatnou
  implementaci a ověření kompatibility s PDF/A-3b.
- Unit testy: `python -m unittest test_cert_chain` v adresáři Bridge.

**Vydání 2.3.1:** INSTALL_AND_START.bat má připnutý ověřený
commit a SHA-256, včetně kontroly očekávané verze. Automatizované testy
ověřují skutečný podpis PDF s jedním lokálním TEST časovým razítkem a
vložení celého řetězce CA do CMS. Test instalátoru hlídá kontrolní
součty všech osmi stahovaných souborů.

**Zbývá ověření v prostředí uživatele:** vytvořit PDF s Windows/USB QSCD
certifikátem, ověřit jej v DSS a v programu, který dříve hlásil
„neplatný“, a vyzkoušet dávku proti lokální TEST TSA před placeným razítkem.
Přítomnost řetězce CA sama o sobě nezaručuje právní ani validační status.


## PDF Validator – detailní výsledky 2.3.2

Samostatná, výhradně čtecí kontrola `pdf_signature_inspector.py` zobrazuje:
- podpisová pole, formát CMS /SubFilter a pokrytí celého PDF,
- počet certifikátů vložených v CMS a počet podpisových časových razítek,
- přítomnost revokačních atributů uvnitř CMS (Adobe/ETSI),
- počet OCSP, CRL a certifikátů uložených v PDF slovníku /DSS,
- rozpory s nezávislými výsledky veraPDF a EU DSS, s vysvětlujícími varováními.

**Přítomnost není platnost.** Parser nerozhoduje o kvalifikaci certifikátu, odvolání, důvěryhodnosti certifikačních autorit ani pravosti razítka. Tyto závěry přebírá výhradně z EU DSS. Stav **NEOVĚŘENO** není totéž jako **NEPLATNÉ**. PDF bez lokálních OCSP/CRL může být v EU DSS platné díky online ověření. Samotná přítomnost /DSS zase nedokazuje PAdES-LT.

Kontrola žádná razítka nevydává, nečte privátní klíče a neprovádí podpisy. Všechny vyhodnocované PDF zůstávají v lokálním AuthorizationBridge. Testy vytvářejí vlastní testovací certifikáty a jeden bezplatný lokální testovací timestamp.

Rozhraní nabízí rozbalovací přehled ke každému PDF a TXT report. Nový instalátor přidává `pdf_signature_inspector.py` s ověřením SHA-256. Verze bridge musí být **2.3.2 nebo novější**.

Doporučený závěrečný test: ověřit PDF vytvořené na konkrétním počítači se skutečným QSCD certifikátem a porovnat výsledek se zprávou EU DSS i s programem, který hlásil „neplatný podpis“. Tento test nebylo možné provést bez přístupu k danému certifikátu a programu.


## EU DSS první spuštění – diagnostika 2.3.3

Pokud PDF/A-3b vyhovuje, ale kryptografie, QES a QTSA jsou „NEOVĚŘENO“,
zkontroluj detail reportu. Hláška „EU DSS se nespustilo“ znamená,
že nezávislý server DSS **nebyl dostupný**. Není to potvrzení neplatnosti
podpisu ani časového razítka.

V rozhraní se nyní odlišuje „DSS nainstalováno“ od „DSS server běží“.
Startovací výstup Java/Tomcat se ukládá do lokálního souboru
`%LOCALAPPDATA%\\20-20-TOOLBOX\\EU-DSS\\6.5\\startup.log`.
Při návratovém kódu chyby skončí kontrola dříve; časový limit spuštění
je 240 sekund. Při chybě lze otevřít `startup.log` a také adresář
`apache-tomcat-*\\logs` pod instalací EU DSS. Nevyžaduje to
nový podpis ani žádost o placené časové razítko.

Nadále je potřeba reálný test spuštění na Windows uživatele, zejména
kvůli místní instalaci Javy, firemnímu antiviru a případnému obsazení
portu 18080. Neverifikovaný výsledek se nesmí vydávat za platný.

## Oprava rozbité konfigurace EU DSS 6.5 (Bridge 2.3.4)

Původní instalační skript mohl při změně Tomcat HTTP portu z 8080 na
18080 vložit atribut `address="127.0.0.1"` za uzavírací lomítko XML
`<Connector ... />`. To poškodilo soubor `server.xml` a Tomcat při
spuštění hlásil SAXParseException, čímž validace čekala na nedostupné API.

- Nová instalace nastavuje atributy pomocí parseru XML (nikoliv vložením
  textu před znak `>`) a ověřuje uložení a vazbu na localhost.
- **Již nainstalované EU DSS není potřeba znovu stahovat.** Při další
  validaci nový Bridge opraví jen přesně rozpoznanou starou chybu,
  ověří výsledné XML a zachová zálohu `server.xml.before-2020-repair.bak`.
- Neznámé změny a jiné typy chyb XML neopravujeme automaticky.
  Vyžadují diagnostiku podle `apache-tomcat-*/logs/catalina*.log`.
- Oprava nevytváří nové podpisy, nevydává časová razítka, nemění PDF/A
  a nemění pravidla EU DSS pro QES a QTSA.

Po aktualizaci AuthorizationBridge na **2.3.4** spusť kontrolu znovu a
sleduj skutečný stav EU DSS. Přesný výsledek kryptografické a kvalifikované
validace se dozvíš až po úspěšném spuštění EU DSS.
