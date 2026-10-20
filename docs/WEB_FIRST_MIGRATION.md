# 2020Toolbox – web-first, multiplatformní migrace

## Cíl
Webové UI a aktualizace bez opakovaného stahování BAT. Podepisování se používá
na jednom vyhrazeném Windows PC; ostatní zařízení (včetně macOS) mohou
připravovat dokumenty a používat funkce, které nevyžadují přístup ke klíči.

## Současný stav (ověřeno v repozitáři)
- Frontend již běží z webu, převod PDF/A probíhá ve WASM.
- PAdES podpis používá službu `127.0.0.1:8094` a Windows Certificate Store.
- Soukromý klíč zůstává ve Windows, což je nutné zachovat.
- PDF Validator dnes spoléhá na lokální Bridge, pyHanko, veraPDF a EU DSS.
- Instalační BAT ověřuje pevně připnuté SHA-256, nelze ho bezpečně nahradit
  automatickým spouštěním libovolného kódu z větve `main`.

## Cílová architektura
1. Statické frontend moduly a jejich vydání: webový hosting (bez instalace).
2. Validace: samostatná serverová API služba (pyHanko + EU DSS + veraPDF).
   Vyžaduje autentizaci, limity velikostí, omezení času, izolaci parserů,
   nepersistentní vstupy a bezpečné mazání souborů.
3. Podpis: zachovat lokálního signera na jediném Windows PC; jednorázově
   registrovat službu s bezpečnou aktualizací podle podepsaného release manifestu.
   Alternativa bez jakékoli lokální služby: kvalifikovaný vzdálený poskytovatel
   s podporou CSC a podepisování přes jeho API.
4. PDF/A zůstane v prohlížeči, případně se přesune na server jako fallback.
5. Veřejná webová stránka nesmí exposeovat privátní klíče, PFX, PIN
   ani přímé neautentizované signing endpointy.

## Proč nyní nejde slíbit nulovou instalaci pro USB/Windows certifikát
Browser neposkytuje obecný přístup k privátním klíčům Windows Certificate Store,
SmartCard API ani každému QSCD tokenu. Bez lokální služby či vzdáleného
poskytovatele nelze stávající podpisovou cestu zachovat.

## Etapy realizace
- Etapa 1 (tento PR): správné multiplatformní UI a žádný BAT na Macu.
- Etapa 2: hostovaná validační služba včetně izolace a regresních testů.
- Etapa 3: jednorázově instalovaný, automaticky aktualizovaný signing agent
  **nebo** vzdálený CSC signer.
- Etapa 4: integrační ověření na Macu, Windows, a reálném QES/QTSA.

## Akceptační kritéria
- macOS nevykazuje instalační tlačítko BAT.
- Příprava PDF je na macOS dostupná i bez Bridge.
- Validace na Macu musí být skutečná serverová validace (nikoli falešně zelené UI).
- Přístup k podpisovému klíči mimo podpisový PC je zakázaný.
- Výsledky QES/QTSA pocházejí z nezávislé validace EU DSS.
- Nová verze webového UI se projeví bez dalšího instalačního BAT.
