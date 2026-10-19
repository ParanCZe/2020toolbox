# 20-20 AuthorizationBridge

Lokální podpisový backend pro **20-20 TOOLBOX → Autorizace PDF**.

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


## Vývojová změna 2.4.0 – certifikační řetězec Windows a PAdES B-LT

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
- Původní PAdES B-B a B-T zůstávají dostupné. Nová výslovná volba
  **PAdES B-LT** přes `ValidationContext(allow_fetching=True, revocation_mode="hard-fail")`
  načítá validační odpovědi a ukládá je do **DSS téže podpisové revize**
  (`TOGETHER_WITH_SIGNATURE`, bez VRI), aby se PDF neměnilo až po podpisu.
- LT používá pouze kořen CA potvrzený úložištěm Windows bez výjimky
  `AllowUnknownCertificateAuthority`. To, že je certifikát přiložen k PDF,
  samo o sobě nestačí k jeho důvěryhodnosti.
- **PAdES-LT není PAdES-LTA.** Nevydává se další archivní TSA razítko.
  Revokační podklady musí být v daném okamžiku dostupné a validační pravidla
  v cílovém prohlížeči mohou být odlišná.
- Pokud OCSP/CRL nelze načíst nebo ověřit, režim LT selže; nelze automaticky
  znovu žádat o ostré razítko bez souhlasu.
- PAdES B-LT je dostupné v UI až s Bridgem 2.4.0+ a flagy
  `pades_lt`, `windows_cert_chain_embedding`.
- Unit testy: `python -m unittest discover -s AuthorizationBridge -p 'test_*.py' -v` v kořeni repozitáře. CI spouští také test skutečného B-B/B-T podpisu s lokální TEST TSA.

**Release:** Produkční INSTALL_AND_START.bat používá připnutý commit a
SHA-256. Po otestování změny je nutné udělat samostatný release krok:
aktualizovat pin, SHA-256, očekávanou verzi a kontrolovat validitu nového
podepsaného PDF ve DSS i v programu, který původně hlásil neplatnost.
