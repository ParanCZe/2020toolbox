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
