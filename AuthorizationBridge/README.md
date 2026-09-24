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

Výstupní soubory mají vždy suffix `_EAR.pdf`; bridge suffix kontroluje i na backendu, aby se nepřidal dvakrát.


## Security hardening v1.5

AuthorizationBridge stále naslouchá pouze na `127.0.0.1:8094`, ale navíc odmítá podpisové požadavky z neznámých webových originů. Povolený Toolbox si při otevření vyžádá náhodný in-memory session token a každý citlivý POST musí tento token poslat v hlavičce `X-20-20-Session`.

- wildcard CORS (`Access-Control-Allow-Origin: *`) byl odstraněn,
- session token se po restartu bridge vždy změní a neukládá se na disk,
- PFX/P12 a heslo se neposílají na GitHub ani jiný aplikační server,
- PFX se při načtení krátce zapíše do lokálního dočasného souboru a ihned se odstraní,
- při PAdES B-T komunikuje bridge s uživatelem zadaným TSA serverem; ten dostává timestamp request založený na kryptografickém otisku, nikoli privátní klíč.

## Rychlý batch export

Autorizace používá až dva samostatné Web Workery s Ghostscript WASM, takže na vhodném desktopu mohou běžet dva PDF/A-3b převody současně. Parametry převodu a ICC profil jsou stejné jako v původním převodu; nezavádí se nižší DPI ani rasterizační režim. Výsledný ZIP používá STORE místo zbytečné druhé komprese již komprimovaných PDF.
