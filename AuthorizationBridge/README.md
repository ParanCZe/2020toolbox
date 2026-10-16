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

## Optional signing convenience (v2.2.0)

- **PostSignum TSA credentials:** Clicking `Uložit údaje bezpečně` encrypts the login, exact HTTPS PostSignum TSA URL, and password with Windows **CurrentUser DPAPI** and stores the ciphertext in `%LOCALAPPDATA%\\20-20-TOOLBOX\\AuthorizationBridge\\tsa-credentials.dpapi`. The password is never included in a status response or localStorage; credentials are decrypted only in the bridge for matching PostSignum requests. The user can erase the vault with the dedicated button. The USB token PIN is never saved.
- **Opt-in approval session:** On the first batch, Windows asks the user to explicitly approve both that batch and at most 20 further batches over 15 minutes. Subsequent batches still need an explicit click on `Podepsat`; each uses a separate one-shot authorization token linked to the exact SHA-256 hashes, output names, metadata, visible stamp and positions. The grant expires and is lost on service restart or when disabled.
- Security: both features require the trusted browser Origin and bridge session token, with the approval grant also bound to a per-page random session ID and the signing certificate / TSA account. Nothing runs automatically in the background. The private RSA signing handle remains managed exclusively by Windows.

**Regression checks before using PostSignum in production:** test 3 PDFs using local TEST TSA (expected count 3/3); verify all resulting PAdES signatures; test the initial confirmation and subsequent automatic confirmation in the same page session; restart bridge and confirm that Windows again asks for approval; confirm that the vault password is no longer visible in the browser and the USB token still controls PIN prompts. The code does not modify `bytes_reserved=262144` or the non-consuming TSA connectivity preflight.
