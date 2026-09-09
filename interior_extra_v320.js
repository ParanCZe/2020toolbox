(()=>{
  const data=window.TOOLBOX_INTERIOR_STANDARDS_V314Y;
  if(!Array.isArray(data)) return;
  const rows=[];
  const add=(cat,status,items)=>items.forEach((x,i)=>rows.push({id:`int320-${cat}-${x[0]}`,cat,status,title:x[1],recommended:x[2],minimum:x[3]||'',note:x[4]||'',keywords:x[5]||[]}));

  add('kuchyne','DOPORUČENÍ',[
    ['landing-hob','Odkládací plocha u varné desky','min. 300 mm na každé straně','alespoň 300 mm na jedné straně','Pro bezpečné odložení hrnců a náčiní.',['kuchyně','varná deska','odkládací plocha']],
    ['landing-sink','Odkládací plocha u dřezu','450–600 mm','cca 300 mm','Praktické pro nádobí a přípravu.',['kuchyně','dřez','odkládací plocha']],
    ['landing-fridge','Odkládací plocha u lednice','400–600 mm v dosahu','krátká plocha poblíž','Usnadňuje vykládání nákupu.',['kuchyně','lednice','pracovní plocha']],
    ['dishwasher-gap','Myčka vedle dřezu','ideálně bezprostředně vedle','do cca 900 mm','Zkracuje přenos mokrého nádobí.',['kuchyně','myčka','dřez']],
    ['dishwasher-front','Prostor před otevřenou myčkou','1000–1200 mm','cca 900 mm','Aby šel kolem otevřených dvířek projít člověk.',['kuchyně','myčka','průchod']],
    ['oven-front','Manipulační prostor před troubou','1000–1200 mm','cca 900 mm','Důležité pro bezpečné vyjmutí horkých plechů.',['kuchyně','trouba','prostor']],
    ['fridge-front','Prostor před lednicí','1000–1200 mm','cca 900 mm','U americké lednice ověř otevření obou dveří.',['kuchyně','lednice','průchod']],
    ['corner-deadspace','Rohová mezera u dvířek','40–80 mm podle kování','dle výrobce','Brání kolizi úchytek a sousedních čel.',['kuchyně','roh','dvířka']],
    ['tall-unit-clearance','Průchod před vysokými skříněmi','1000–1200 mm','cca 900 mm','Pro komfortní otevírání lednice, spíže a trouby.',['kuchyně','vysoká skříň','průchod']],
    ['drawer-front','Prostor před plně vysunutou zásuvkou','900–1100 mm','cca 800 mm','U protilehlé linky ověř souběh zásuvek.',['kuchyně','zásuvka','průchod']],
    ['bar-seat-depth','Hloubka místa pro barovou židli','450–550 mm','cca 400 mm','Počítá se se zasunutím a odstupem od průchodu.',['bar','židle','kuchyně']],
    ['bar-back-clearance','Průchod za barovým sezením','900–1100 mm','cca 800 mm','Při frekventovaném průchodu raději 1000 mm a více.',['bar','průchod','kuchyně']],
    ['pantry-depth','Hloubka spížní skříně','350–600 mm','cca 300 mm','Mělčí police zlepšují přehlednost zásob.',['spíž','skříň','hloubka']],
    ['pantry-shelf','Rozteč polic ve spíži','250–350 mm','dle obsahu','Vyšší lahve a spotřebiče potřebují lokálně více.',['spíž','police','rozteč']],
    ['toe-kick-depth','Ustoupení kuchyňského soklu','50–90 mm','cca 40 mm','Zvětšuje prostor pro špičky chodidel.',['kuchyně','sokl','ergonomie']],
    ['backsplash','Výška obkladu za pracovní deskou','500–650 mm','dle horních skříněk','U varné zóny respektuj požadavky materiálu a spotřebiče.',['kuchyně','obklad','pracovní deska']]
  ]);

  add('koupelna','DOPORUČENÍ',[
    ['double-basin-axis','Rozteč os dvou umyvadel','600–750 mm','cca 550 mm','Komfort pro současné používání.',['umyvadlo','dvojité','koupelna']],
    ['basin-wall','Osa umyvadla od boční stěny','450 mm a více','cca 400 mm','Více prostoru pro lokty a úklid.',['umyvadlo','stěna','odstup']],
    ['basin-counter','Volná deska vedle umyvadla','150–300 mm','cca 100 mm','Praktická plocha na kosmetiku a drobnosti.',['umyvadlo','deska','koupelna']],
    ['shower-niche','Výška niky ve sprše','900–1200 mm','dle uživatele','Umísti mimo hlavní proud vody.',['sprcha','nika','výška']],
    ['shower-head','Výška hlavové sprchy','2000–2200 mm','dle postavy','U vysokých uživatelů raději více.',['sprcha','hlavice','výška']],
    ['shower-mixer','Výška sprchové baterie','1000–1200 mm','dle výrobku','Ovládání má být dosažitelné bez vstupu pod proud.',['sprcha','baterie','výška']],
    ['tub-faucet','Výška baterie u vany','cca 650–850 mm','dle vany','Přizpůsob typu baterie a obkladu.',['vana','baterie','výška']],
    ['toilet-paper','Dosah držáku toaletního papíru','200–300 mm před osou WC','v pohodlném dosahu','Nemá vyžadovat výrazné vytáčení trupu.',['wc','držák','dosah']],
    ['towel-basin','Držák ručníku u umyvadla','do cca 600 mm od umyvadla','v dosahu paže','Minimalizuje kapání vody po podlaze.',['ručník','umyvadlo','koupelna']],
    ['towel-shower','Ručník od výstupu ze sprchy','do cca 600–800 mm','v bezpečném dosahu','Neměl by být nutný krok po mokré podlaze.',['sprcha','ručník','dosah']],
    ['laundry-sort','Šířka třídicího koše na prádlo','300–450 mm/modul','dle systému','Více košů umožní třídění před praním.',['prádlo','koš','koupelna']],
    ['dryer-stack','Výška věže pračka + sušička','cca 1700–1900 mm','dle spotřebičů','Ovládání horního spotřebiče musí zůstat v dosahu.',['pračka','sušička','věž']],
    ['vanity-depth','Hloubka koupelnové skříňky s umyvadlem','450–550 mm','cca 400 mm','U úzké koupelny lze použít mělčí umyvadlo.',['koupelna','skříňka','hloubka']],
    ['mirror-width','Šířka zrcadla nad umyvadlem','min. šířka umyvadla','cca 500 mm','U dvojitého umyvadla často souvislé zrcadlo.',['zrcadlo','umyvadlo','šířka']],
    ['cabinet-depth','Hloubka zrcadlové skříňky','120–180 mm','cca 100 mm','Dostatečné pro kosmetiku bez výrazného vystoupení.',['zrcadlová skříňka','hloubka']],
    ['heated-rail','Výška koupelnového žebříku','spodní hrana cca 300–500 mm','dle výrobce','Nezakrývat nábytkem a ponechat prostor pro ručníky.',['radiátor','žebřík','koupelna']]
  ]);

  add('ulozne','DOPORUČENÍ',[
    ['wardrobe-aisle','Průchod před šatní skříní','900–1100 mm','cca 800 mm','U protilehlých skříní zvaž 1000–1200 mm.',['šatna','průchod','skříň']],
    ['walkin-two-side','Ulička mezi dvěma řadami skříní','1000–1200 mm','cca 900 mm','Umožňuje pohodlné otevírání a oblékání.',['šatna','ulička']],
    ['walkin-one-side','Ulička v jednostranné šatně','900–1000 mm','cca 800 mm','Pro běžné oblékání jedné osoby.',['šatna','průchod']],
    ['shoe-shelf','Rozteč polic na nízkou obuv','180–220 mm','cca 160 mm','Kozačky vyžadují samostatnou vyšší zónu.',['botník','police','obuv']],
    ['boot-space','Výška pro vysoké boty','400–550 mm','dle obuvi','Vhodné u spodní části botníku.',['boty','kozačky','výška']],
    ['linen-depth','Hloubka skříně na ložní prádlo','400–500 mm','cca 350 mm','Příliš hluboké police zhoršují přehlednost.',['ložní prádlo','skříň','hloubka']],
    ['linen-spacing','Rozteč polic na ručníky a prádlo','250–350 mm','dle obsahu','Pro velké deky může být více.',['police','prádlo','ručníky']],
    ['drawer-underwear','Výška zásuvky na drobné prádlo','100–160 mm','dle kování','Mělké zásuvky zlepšují přehled.',['zásuvka','prádlo','skříň']],
    ['drawer-knitwear','Výška zásuvky na svetry','180–250 mm','dle obsahu','Vyšší zásuvka pojme objemnější textil.',['zásuvka','svetr','skříň']],
    ['hanger-rod','Výška běžné šatní tyče','1600–1750 mm','dle uživatele','Pro děti nebo nižší uživatele sniž.',['šatní tyč','výška','šatna']],
    ['double-rod-low','Spodní tyč při dvojitém zavěšení','cca 900–1000 mm','dle oděvů','Pro košile a kalhoty.',['šatní tyč','dvojitá','výška']],
    ['double-rod-high','Horní tyč při dvojitém zavěšení','cca 1750–1850 mm','dle uživatele','Musí zůstat dosažitelná.',['šatní tyč','horní','výška']],
    ['bag-shelf','Výška police na kabelky','250–350 mm','dle velikosti','Při vyšší polici použij přepážky.',['kabelky','police','šatna']],
    ['suitcase-shelf','Police na kufry','hloubka 500–650 mm','cca 450 mm','Často vhodná v horní nebo spodní zóně.',['kufr','police','hloubka']],
    ['cleaning-closet','Šířka skříně na vysavač a úklid','400–600 mm','cca 350 mm','Počítej s výškou tyčí, mopu a vysavače.',['úklid','vysavač','skříň']],
    ['broom-height','Světlá výška úklidové skříně','1400–1800 mm','dle vybavení','Dlouhé nástroje potřebují nepřerušenou výšku.',['koště','mop','skříň']]
  ]);

  add('predsin','DOPORUČENÍ',[
    ['bench-height','Výška lavice v předsíni','430–480 mm','cca 420 mm','Pohodlná pro obouvání.',['předsíň','lavice','výška']],
    ['bench-depth','Hloubka lavice v předsíni','350–450 mm','cca 300 mm','Mělčí lavice šetří průchod.',['předsíň','lavice','hloubka']],
    ['coat-hook','Výška háčků pro dospělé','1500–1700 mm','dle uživatelů','Dětské háčky dej přibližně 900–1200 mm.',['háček','kabát','předsíň']],
    ['mirror-full','Výška celopostavového zrcadla','cca 1600–1800 mm','spodní hrana nízko','Zajisti odstup pro kontrolu celé postavy.',['zrcadlo','předsíň']],
    ['shoe-change','Volný prostor pro obouvání','800 × 800 mm a více','cca 700 × 700 mm','Nemá blokovat hlavní vstupní dveře.',['obouvání','předsíň','prostor']],
    ['door-cabinet','Odstup skříně od křídla vstupních dveří','min. 100 mm od dráhy křídla','bez kolize','Ověř kliky, zárubně a otevření na 90°.',['dveře','skříň','předsíň']],
    ['key-shelf','Výška odkládací police na klíče','900–1200 mm','dle uživatele','Prakticky u vstupu, ale mimo dosah malých dětí.',['klíče','police','předsíň']],
    ['umbrella','Prostor na deštníky','výška cca 600–800 mm','dle stojanu','Umísti poblíž vstupu a na omyvatelném povrchu.',['deštník','předsíň']],
    ['bag-drop','Odkládací plocha na tašku','výška 750–950 mm','dle řešení','Užitečná při příchodu a odemykání.',['taška','odkládací plocha','předsíň']],
    ['stroller','Prostor pro kočárek','cca 700 × 1200 mm','dle modelu','Nemá zužovat únikovou nebo hlavní komunikační trasu.',['kočárek','předsíň','prostor']],
    ['bike-indoor','Prostor pro zavěšené kolo','šířka cca 600–800 mm','dle kola','Ověř délku, výšku a manipulaci při zavěšování.',['kolo','předsíň','úložné']],
    ['mail-zone','Odkládací zóna na poštu','šířka 300–500 mm','dle dispozice','Pomáhá udržet vstupní část přehlednou.',['pošta','odkládání','předsíň']],
    ['charging','Nabíjecí zásuvka u vstupu','cca 900–1200 mm','dle nábytku','Pro telefon, sluchátka nebo vysavač.',['zásuvka','nabíjení','předsíň']],
    ['floor-mat','Hloubka vstupní čisticí zóny','1200–1800 mm','cca 900 mm','Delší zóna lépe zachytí nečistoty.',['rohož','vstup','předsíň']],
    ['console-depth','Hloubka konzolového stolku','250–350 mm','cca 200 mm','Mělčí kus zachová průchod.',['konzole','stolek','předsíň']],
    ['clear-width','Volný hlavní průchod předsíní','1000–1200 mm','cca 900 mm','U více dveří a provozu je vhodné více.',['průchod','předsíň','šířka']]
  ]);

  add('loznice','DOPORUČENÍ',[
    ['bed-side-comfort','Komfortní průchod vedle postele','700–900 mm','cca 600 mm','Na obou stranách dvoulůžka ideálně stejně.',['postel','průchod','ložnice']],
    ['bed-foot-comfort','Komfortní průchod u nohou postele','900–1100 mm','cca 700 mm','Více pokud je naproti skříň.',['postel','průchod','ložnice']],
    ['wardrobe-bed','Postel proti skříni s otočnými dveřmi','1000–1200 mm','cca 900 mm','Pro otevření dveří a současný průchod.',['postel','skříň','ložnice']],
    ['wardrobe-slider','Postel proti skříni s posuvnými dveřmi','900–1000 mm','cca 800 mm','Posuvné dveře umožní menší mezeru.',['postel','skříň','ložnice']],
    ['nightstand-height','Výška nočního stolku','v úrovni matrace ±100 mm','dle postele','Usnadní dosah vleže.',['noční stolek','výška','ložnice']],
    ['nightstand-width','Šířka nočního stolku','400–600 mm','cca 300 mm','Pro lampu, telefon a sklenici.',['noční stolek','šířka','ložnice']],
    ['reading-lamp','Výška čtecí lampy u postele','světlo cca 900–1200 mm nad podlahou','dle postele','Směřovat na knihu, ne do očí druhé osoby.',['lampa','čtení','postel']],
    ['switch-bed','Vypínač dosažitelný z postele','cca 700–1000 mm','dle nábytku','Ideální pro hlavní světlo i lampičku.',['vypínač','postel','ložnice']],
    ['socket-bed','Zásuvka u nočního stolku','cca 600–800 mm nebo nad deskou','dle stolku','Aby nebyla skrytá za nábytkem.',['zásuvka','postel','ložnice']],
    ['tv-distance','Vzdálenost TV od postele','cca 2–3× výška obrazu','dle obrazovky','Záleží na rozlišení a velikosti TV.',['tv','postel','vzdálenost']],
    ['dresser-front','Prostor před komodou','800–1000 mm','cca 700 mm','Pro plné vysunutí zásuvek a stání.',['komoda','zásuvka','ložnice']],
    ['crib-parent','Průchod u dětské postýlky','700–900 mm','cca 600 mm','Umožní manipulaci s dítětem.',['postýlka','průchod','ložnice']],
    ['blackout-box','Prostor pro závěs před radiátorem','min. 50–100 mm od radiátoru','bez kolize','Dlouhé závěsy nesmí blokovat topení.',['závěs','radiátor','ložnice']],
    ['window-bed','Odstup postele od studeného okna','200–400 mm podle konstrukce','bez kolize','Zohledni parapet, závěsy a proudění vzduchu.',['postel','okno','odstup']],
    ['make-bed','Manipulační prostor pro stlaní','min. 600 mm na přístupné straně','cca 500 mm','U hotelu je vhodné více kvůli úklidu.',['postel','stlaní','průchod']],
    ['bench-foot','Lavice u nohou postele','mezera 100–200 mm od postele','bez kolize','Za lavicí ponech průchod.',['lavice','postel','ložnice']]
  ]);

  add('obyvak','DOPORUČENÍ',[
    ['sofa-table','Sedačka – konferenční stolek','400–500 mm','cca 350 mm','Pohodlný dosah a průchod pro nohy.',['sedačka','stolek','obývák']],
    ['sofa-wall','Průchod za volně stojící sedačkou','800–1000 mm','cca 700 mm','Pro hlavní trasu raději 900 mm a více.',['sedačka','průchod','obývák']],
    ['armchair-table','Křeslo – odkládací stolek','100–300 mm','v dosahu ruky','Stolek by měl být přibližně ve výšce područky.',['křeslo','stolek','obývák']],
    ['tv-center','Výška středu TV','cca 900–1200 mm','dle sezení','Střed obrazu přibližně v úrovni očí vsedě.',['tv','výška','obývák']],
    ['tv-65','Vzdálenost pro 65″ TV','cca 2,0–3,0 m','dle rozlišení','4K umožňuje kratší vzdálenost.',['tv','65','vzdálenost']],
    ['tv-75','Vzdálenost pro 75″ TV','cca 2,3–3,4 m','dle rozlišení','Přizpůsob velikosti obrazu a zornému poli.',['tv','75','vzdálenost']],
    ['rug-sofa','Koberec pod sedací sestavou','přední nohy sedačky na koberci','koberec alespoň pod stolem','Větší koberec vizuálně sjednotí sestavu.',['koberec','sedačka','obývák']],
    ['bookshelf-sofa','Odstup sedačky od knihovny','900–1100 mm při otevírání','cca 800 mm','Pro posuvná dvířka může být menší.',['sedačka','knihovna','průchod']],
    ['fireplace-front','Volný prostor před krbem','1000–1500 mm','dle výrobce','Respektuj bezpečné vzdálenosti konkrétního spotřebiče.',['krb','prostor','obývák']],
    ['fireplace-seat','Sedačka od krbu','dle tepelného výkonu, často 1500 mm a více','dle výrobce','Neumisťuj hořlavý nábytek v zakázané zóně.',['krb','sedačka','vzdálenost']],
    ['floor-lamp','Prostor pro stojací lampu','cca 350–500 mm půdorysně','dle lampy','Umísti mimo hlavní průchod.',['lampa','obývák','prostor']],
    ['sideboard-front','Prostor před komodou/sideboardem','800–1000 mm','cca 700 mm','Pro otevření dvířek a zásuvek.',['komoda','průchod','obývák']],
    ['console-sofa','Konzole za sedačkou','hloubka 250–400 mm','cca 200 mm','Vhodná na světlo, dekorace nebo zásuvky.',['konzole','sedačka','obývák']],
    ['conversation','Vzdálenost protilehlého sezení','cca 1800–2600 mm','dle sestavy','Příliš velká vzdálenost zhoršuje konverzaci.',['sezení','konverzace','obývák']],
    ['ottoman-gap','Sedačka – taburet','350–500 mm','cca 300 mm','Dle toho, zda taburet slouží k nohám nebo jako stolek.',['taburet','sedačka','obývák']],
    ['curtain-return','Boční přesah závěsu za okno','150–300 mm na stranu','dle okna','Pomáhá plnému odkrytí zasklení.',['závěs','okno','obývák']]
  ]);

  add('pracovna','DOPORUČENÍ',[
    ['desk-depth-2mon','Hloubka stolu pro dva monitory','800–900 mm','cca 700 mm','Zlepší vzdálenost očí od obrazovek.',['stůl','monitor','pracovna']],
    ['desk-width-2mon','Šířka stolu pro dva monitory','1400–1800 mm','cca 1200 mm','Záleží na velikosti monitorů a příslušenství.',['stůl','monitor','šířka']],
    ['monitor-eye','Horní hrana monitoru','v úrovni očí nebo mírně níž','dle uživatele','Omezuje zaklánění hlavy.',['monitor','ergonomie','oči']],
    ['monitor-distance','Vzdálenost očí od monitoru','500–800 mm','cca délka paže','Větší úhlopříčka může vyžadovat více.',['monitor','vzdálenost','pracovna']],
    ['keyboard','Vzdálenost klávesnice od hrany stolu','100–150 mm','cca 80 mm','Ponechá oporu pro zápěstí a předloktí.',['klávesnice','stůl','ergonomie']],
    ['mouse','Plocha pro myš','min. 250 × 250 mm','cca 200 × 200 mm','Pro nízkou citlivost může být výrazně větší.',['myš','pracovna','plocha']],
    ['chair-back','Prostor za pracovní židlí','900–1200 mm','cca 800 mm','Více pokud za židlí vede průchod.',['židle','pracovna','průchod']],
    ['visitor-chair','Prostor pro návštěvní židli','cca 600 × 600 mm','dle židle','Před stolem ponech místo i pro odsunutí.',['židle','návštěva','pracovna']],
    ['file-cabinet','Prostor před zásuvkovým archivem','900–1100 mm','cca 800 mm','Pro plné vysunutí zásuvek.',['archiv','zásuvka','pracovna']],
    ['printer','Police pro tiskárnu','hloubka 450–600 mm','dle zařízení','Počítej s vysunutím zásobníků a kabely.',['tiskárna','police','pracovna']],
    ['acoustic-wall','Plocha akustického pohlcení v malé pracovně','orientačně 15–30 % povrchů','dle akustiky','Měkké prvky a panely omezí odrazy při hovorech.',['akustika','pracovna','panel']],
    ['webcam','Výška webkamery','cca v úrovni očí','dle monitoru','Přirozenější perspektiva při videohovorech.',['webkamera','monitor','pracovna']],
    ['task-light','Pracovní lampička','500–1000 lx lokálně','dle činnosti','Neoslňovat monitor ani uživatele.',['osvětlení','pracovna','lux']],
    ['desk-socket','Zásuvky nad/na pracovním stole','2–4 zásuvky + data podle provozu','min. dle techniky','Vyhni se prodlužkám přes průchod.',['zásuvka','stůl','pracovna']],
    ['sit-stand','Rozsah výškově stavitelného stolu','cca 650–1250 mm','dle uživatelů','Rozsah má pokrýt pohodlnou práci vsedě i ve stoje.',['stůl','výškově stavitelný','pracovna']],
    ['standing-mat','Prostor pro stání u výškového stolu','cca 700 × 700 mm','cca 600 × 600 mm','Bez kolizí s kabely a zásuvkovým kontejnerem.',['stání','pracovna','prostor']]
  ]);

  add('jidlo','DOPORUČENÍ',[
    ['seat-width','Šířka místa u jídelního stolu','550–650 mm/osoba','cca 500 mm','Pro pohodlné lokty je vhodné kolem 600 mm.',['jídelní stůl','osoba','šířka']],
    ['seat-depth','Hloubka stolové plochy na osobu','350–450 mm','cca 300 mm','Uprostřed může zůstat plocha na servírování.',['jídelní stůl','hloubka','osoba']],
    ['table-wall','Stůl od stěny bez průchodu','800–900 mm','cca 700 mm','Pro odsunutí židle.',['stůl','stěna','jídelna']],
    ['table-passage','Stůl od stěny s průchodem za židlí','1100–1300 mm','cca 1000 mm','Pro pohodlné míjení za sedící osobou.',['stůl','průchod','jídelna']],
    ['round-4','Průměr kulatého stolu pro 4 osoby','1000–1200 mm','cca 900 mm','Větší průměr zlepší komfort servírování.',['kulatý stůl','4 osoby','jídelna']],
    ['round-6','Průměr kulatého stolu pro 6 osob','1300–1500 mm','cca 1200 mm','U většího průměru může být střed hůř dosažitelný.',['kulatý stůl','6 osob','jídelna']],
    ['rect-4','Obdélníkový stůl pro 4 osoby','1200–1400 × 750–900 mm','cca 1100 × 700 mm','Rozměr závisí na sezení na čelech.',['stůl','4 osoby','jídelna']],
    ['rect-6','Obdélníkový stůl pro 6 osob','1600–2000 × 800–1000 mm','cca 1500 × 750 mm','Pro pohodlné čelo počítej s větší délkou.',['stůl','6 osob','jídelna']],
    ['bench-depth','Hloubka jídelní lavice','400–500 mm','cca 380 mm','S opěradlem přidej konstrukční tloušťku.',['lavice','jídelna','hloubka']],
    ['bench-height','Výška sedáku jídelní lavice','430–470 mm','cca 420 mm','Ladit s výškou stolu.',['lavice','jídelna','výška']],
    ['pendant-height','Spodní hrana závěsného světla nad stolem','600–800 mm nad deskou','cca 550 mm','Nemá bránit výhledu přes stůl.',['světlo','stůl','jídelna']],
    ['sideboard','Prostor před příborníkem','800–1000 mm','cca 700 mm','Pro otevření dvířek a obsluhu.',['příborník','jídelna','průchod']],
    ['buffet','Odkládací plocha pro servírování','hloubka 350–500 mm','cca 300 mm','Praktická u jídelního stolu pro větší domácnost.',['servírování','příborník','jídelna']],
    ['chair-pull','Odsunutí židle od hrany stolu','cca 450–600 mm','cca 400 mm','Při návrhu průchodu počítej s vysunutou židlí.',['židle','stůl','jídelna']],
    ['table-rug','Koberec pod jídelním stolem','přesah min. 600–750 mm za židle','cca 500 mm','Židle zůstane na koberci i po odsunutí.',['koberec','stůl','jídelna']],
    ['wheelchair-end','Volný konec stolu pro vozík','cca 800–900 mm šířky','dle přístupnosti','U veřejných prostor ověř závazné požadavky.',['vozík','stůl','jídelna']]
  ]);

  add('gastro','DOPORUČENÍ',[
    ['aisle-main','Hlavní obslužná ulička v restauraci','1200–1500 mm','cca 1100 mm','Pro obousměrný provoz personálu a hostů.',['restaurace','ulička','gastro']],
    ['aisle-secondary','Vedlejší ulička mezi stoly','900–1100 mm','cca 800 mm','Měřeno s ohledem na odsunuté židle.',['restaurace','stoly','průchod']],
    ['table-gap','Mezera hrana stolu – hrana stolu','1400–1800 mm','cca 1200 mm','Záleží na orientaci židlí a obsluze.',['restaurace','stůl','mezera']],
    ['server-station','Pracovní plocha obslužné stanice','hloubka 450–600 mm','cca 400 mm','Pro příbory, terminál a drobný servis.',['obsluha','stanice','gastro']],
    ['bar-depth','Hloubka barové pracovní desky','600–750 mm','cca 550 mm','Pro vybavení a pracovní zónu barmana.',['bar','pracovní deska','gastro']],
    ['bar-guest','Hloubka pultu pro hosta','300–450 mm','cca 250 mm','Pro nápoj, talíř a lokty.',['bar','pult','host']],
    ['bar-height','Výška barového pultu','1050–1150 mm','cca 1000 mm','Sedák židle typicky 750–800 mm.',['bar','výška','gastro']],
    ['bar-seat','Rozteč barových židlí','550–650 mm/osoba','cca 500 mm','Pro pohodlné lokty raději 600 mm a více.',['bar','židle','rozteč']],
    ['espresso-counter','Výška pracovní desky pro baristu','850–950 mm','dle vybavení','Přizpůsob výšce kávovaru a pracovnímu toku.',['kavárna','barista','kávovar']],
    ['espresso-clear','Volný prostor před kávovarem','1000–1200 mm','cca 900 mm','Pro práci jedné až dvou osob.',['kávovar','průchod','kavárna']],
    ['dish-return','Šířka zóny pro vracení nádobí','900–1200 mm','cca 800 mm','Oddělit od čistého provozu.',['nádobí','gastro','provoz']],
    ['queue','Šířka fronty u pultu','900–1200 mm','cca 800 mm','U samoobsluhy často potřebuje paralelní průchod.',['fronta','pult','gastro']],
    ['tray-rail','Výška lišty na tác','850–950 mm','dle systému','Pohodlná pro dospělého stojícího hosta.',['tác','samoobsluha','výška']],
    ['booth-seat','Výška sedáku boxového sezení','430–470 mm','cca 420 mm','Ladit s výškou stolu.',['box','sedák','restaurace']],
    ['booth-depth','Hloubka sedáku boxu','430–500 mm','cca 400 mm','Příliš hluboký sedák zhoršuje oporu zad.',['box','sedák','hloubka']],
    ['booth-table','Mezera sedák boxu – hrana stolu','cca 250–350 mm horizontálně','dle konstrukce','Ověř pohodlný vstup a prostor pro kolena.',['box','stůl','restaurace']]
  ]);

  add('retail','DOPORUČENÍ',[
    ['main-aisle','Hlavní ulička v prodejně','1400–1800 mm','cca 1200 mm','U vysoké návštěvnosti nebo vozíků raději více.',['retail','ulička','prodejna']],
    ['secondary-aisle','Vedlejší ulička v prodejně','1000–1200 mm','cca 900 mm','Zohledni otevřená dvířka a zákazníky u regálu.',['retail','ulička','regál']],
    ['rack-depth','Hloubka nástěnného regálu','300–600 mm','dle zboží','Větší hloubka zmenšuje průchod.',['retail','regál','hloubka']],
    ['gondola-depth','Hloubka oboustranné gondoly','700–1200 mm','dle systému','Počítej s koncovými čely a manipulační zónou.',['retail','gondola','regál']],
    ['shelf-eye','Prémiová zóna polic','cca 1200–1600 mm','dle cílové skupiny','Nejlépe viditelná a dosažitelná výška.',['retail','police','výška']],
    ['shelf-reach','Horní běžně dosažitelná police','cca 1700–1800 mm','dle uživatelů','Výše umisťuj spíš lehké nebo zásobní zboží.',['retail','police','dosah']],
    ['cash-desk','Výška pokladního pultu pro stojící obsluhu','900–1050 mm','dle provozu','Část pro zákazníka může být odlišná.',['retail','pokladna','výška']],
    ['cash-bag','Odkládací plocha u pokladny','min. 400–600 mm','dle sortimentu','Pro tašku, zboží nebo platební terminál.',['pokladna','odkládací plocha','retail']],
    ['fitting-room','Běžná kabina na zkoušení','cca 1000 × 1200 mm a více','cca 900 × 1000 mm','Přístupná kabina vyžaduje více prostoru.',['kabina','retail','zkoušení']],
    ['mirror-fitting','Zrcadlo ve zkušební kabině','šířka 500–800 mm, výška 1500 mm a více','dle kabiny','Ideálně celopostavové.',['zrcadlo','kabina','retail']],
    ['bench-fitting','Lavice v kabině','výška 430–480 mm, hloubka 300–400 mm','dle prostoru','Pro odložení věcí a obouvání.',['lavice','kabina','retail']],
    ['queue-checkout','Šířka fronty u pokladny','900–1200 mm','cca 800 mm','Nemá blokovat hlavní uličku.',['fronta','pokladna','retail']],
    ['display-table','Výška prezentačního stolu','750–900 mm','dle sortimentu','Pro zboží, které zákazník prohlíží shora.',['retail','stůl','výška']],
    ['display-gap','Průchod kolem prezentačního stolu','1000–1200 mm','cca 900 mm','U obousměrného pohybu více.',['retail','stůl','průchod']],
    ['hanger-rail','Výška oděvní tyče pro zákazníky','1400–1650 mm','dle sortimentu','Dětský sortiment umisťuj níže.',['retail','oděvy','tyč']],
    ['stock-door','Průchod mezi prodejnou a skladem','min. komfortně 900–1000 mm','dle předpisů','Ověř i přepravní vozíky a požární požadavky.',['retail','sklad','dveře']]
  ]);

  add('hotel','DOPORUČENÍ',[
    ['bed-side','Průchod vedle hotelové postele','700–900 mm','cca 600 mm','Pro úklid a manipulaci s lůžkem je vhodné více.',['hotel','postel','průchod']],
    ['bed-foot','Průchod u nohou hotelové postele','900–1100 mm','cca 800 mm','Pokud je naproti nábytek, přidej prostor na dvířka.',['hotel','postel','průchod']],
    ['luggage-bench','Výška lavice na kufr','450–550 mm','cca 400 mm','Pohodlná pro otevírání kufru.',['hotel','kufr','lavice']],
    ['luggage-depth','Hloubka lavice na kufr','450–550 mm','cca 400 mm','Pro běžný kabinový i střední kufr.',['hotel','kufr','hloubka']],
    ['wardrobe-depth','Hloubka hotelové skříně','550–650 mm','cca 500 mm','Pro ramínka a případný trezor.',['hotel','skříň','hloubka']],
    ['desk','Hotelový pracovní stolek','šířka 900–1200 mm, hloubka 450–600 mm','cca 800 × 400 mm','Pro notebook a odkládání.',['hotel','stůl','pracovna']],
    ['minibar','Výška minibaru','ovládání/úchyt cca 600–1000 mm','dle nábytku','Neměl by vyžadovat hluboký předklon.',['hotel','minibar','výška']],
    ['safe','Výška trezoru','cca 900–1400 mm','dle nábytku','Pohodlný dosah bez klečení.',['hotel','trezor','výška']],
    ['coat-hook','Háčky u vstupu do pokoje','1500–1700 mm','dle uživatelů','Doplnit nižší háček pro děti nebo tašky.',['hotel','háček','výška']],
    ['mirror-full','Celopostavové zrcadlo','min. cca 1500 mm vysoké','spodní hrana nízko','Umístit s odstupem pro kontrolu celé postavy.',['hotel','zrcadlo','výška']],
    ['bed-socket','Zásuvky u obou stran lůžka','min. 1–2 zásuvky + USB na každé straně','dle standardu hotelu','Host nemá hledat zásuvku za nábytkem.',['hotel','zásuvka','postel']],
    ['bed-switch','Ovládání hlavního světla od postele','na obou stranách lůžka','alespoň na jedné','Zvyšuje komfort hosta.',['hotel','vypínač','postel']],
    ['bath-hook','Háček v hotelové koupelně','1–2 ks u sprchy + u umyvadla','dle koupelny','Host potřebuje odložit ručník a oděv.',['hotel','koupelna','háček']],
    ['shower-shelf','Odkládací plocha ve sprše','min. cca 200 × 100 mm','dle řešení','Pro šampon a kosmetiku.',['hotel','sprcha','police']],
    ['entry-drop','Odkládací plocha u vstupu','šířka 300–500 mm','dle dispozice','Na kartu, klíče a drobnosti.',['hotel','vstup','odkládání']],
    ['curtain-blackout','Přesah blackout závěsu','150–300 mm za ostění','dle okna','Omezuje boční průnik světla.',['hotel','závěs','blackout']]
  ]);

  add('deti','DOPORUČENÍ',[
    ['desk-3-6','Výška dětského stolku 3–6 let','cca 450–520 mm','dle postavy','Ladit s výškou sedáku.',['děti','stůl','výška']],
    ['chair-3-6','Výška sedáku 3–6 let','cca 260–320 mm','dle postavy','Chodidla mají být opřená.',['děti','židle','výška']],
    ['desk-6-10','Výška stolu 6–10 let','cca 520–640 mm','dle postavy','Ideální je výškově stavitelný nábytek.',['děti','stůl','výška']],
    ['chair-6-10','Výška sedáku 6–10 let','cca 300–380 mm','dle postavy','Kolena přibližně v pravém úhlu.',['děti','židle','výška']],
    ['wardrobe-rail','Dětská šatní tyč','900–1200 mm','dle věku','Podporuje samostatnost dítěte.',['děti','skříň','tyč']],
    ['shelf-reach','Dosažitelná police pro malé dítě','600–1000 mm','dle věku','Těžké věci nedávat vysoko.',['děti','police','dosah']],
    ['toy-bin','Výška boxu na hračky','300–600 mm','dle věku','Dítě má vidět dovnitř a bezpečně manipulovat.',['děti','hračky','box']],
    ['reading-nook','Šířka čtecího koutku','800–1200 mm','cca 700 mm','Doplnit měkké sezení a lokální světlo.',['děti','čtení','koutek']],
    ['play-clear','Volná herní plocha','min. cca 1500 × 1500 mm','dle pokoje','Souvislá plocha je praktičtější než úzké zbytky.',['děti','hraní','prostor']],
    ['bunk-clear','Světlá výška mezi patry palandy','750–900 mm','dle výrobce','Vždy respektuj bezpečnostní pokyny konkrétní palandy.',['palanda','děti','výška']],
    ['bunk-ceiling','Prostor nad horním lůžkem','min. komfortně 750–900 mm','dle výrobce','Dítě má mít prostor se posadit.',['palanda','strop','děti']],
    ['night-light','Noční orientační světlo','nízko u podlahy, cca 150–300 mm','dle řešení','Bez oslnění při nočním pohybu.',['děti','světlo','noc']],
    ['hooks','Výška dětských háčků','800–1200 mm','dle věku','Pro tašku, bundu a pyžamo.',['děti','háček','výška']],
    ['mirror','Výška dětského zrcadla','spodní hrana cca 300–600 mm','dle věku','Bezpečnostní materiál a pevné kotvení.',['děti','zrcadlo','výška']],
    ['bed-side','Průchod u dětské postele','600–800 mm','cca 500 mm','Pro převlékání a stlaní.',['děti','postel','průchod']],
    ['storage-anchor','Kotvení vysokého dětského nábytku','vždy pevně ke stěně','bez výjimky u rizikového nábytku','Zásadní ochrana proti převrácení.',['děti','nábytek','kotvení']]
  ]);

  add('skoly','DOPORUČENÍ',[
    ['desk-gap','Rozestup řad lavic','900–1100 mm','cca 800 mm','Zohledni odsunuté židle a pohyb učitele.',['škola','lavice','průchod']],
    ['teacher-zone','Volná zóna před tabulí','1200–1800 mm','cca 1000 mm','Pro učitele, prezentaci a pohyb před třídou.',['škola','tabule','prostor']],
    ['board-bottom','Spodní hrana tabule','700–900 mm','dle věku žáků','U malých dětí nižší.',['škola','tabule','výška']],
    ['board-top','Horní hrana tabule','1800–2200 mm','dle prostoru','Musí být čitelná ze zadních řad.',['škola','tabule','výška']],
    ['student-table','Hloubka školní lavice','500–650 mm','cca 450 mm','Pro sešit, učebnici a notebook.',['škola','lavice','hloubka']],
    ['student-width','Šířka místa žáka','600–750 mm','cca 550 mm','U počítače více.',['škola','žák','šířka']],
    ['bag-zone','Prostor na školní tašku','cca 300 × 400 mm/žák','dle systému','Nemá zasahovat do uličky.',['škola','taška','úložné']],
    ['coat-hook','Výška šatních háčků pro děti','1000–1400 mm','dle věku','Pro starší žáky více.',['škola','háček','výška']],
    ['cubby','Šířka boxu ve školní šatně','250–350 mm/žák','cca 220 mm','Podle typu oděvu a tašek.',['škola','šatna','box']],
    ['reading-table','Stůl ve školní knihovně','výška cca 720–750 mm','dle věku','Dětské zóny mohou mít nižší nábytek.',['škola','knihovna','stůl']],
    ['library-aisle','Ulička mezi regály školní knihovny','1000–1200 mm','cca 900 mm','Pro skupinový provoz více.',['škola','knihovna','ulička']],
    ['computer-desk','Hloubka počítačového stolu','700–800 mm','cca 650 mm','Pro monitor a pracovní plochu.',['škola','počítač','stůl']],
    ['computer-gap','Rozestup počítačových míst','700–900 mm/osoba','cca 650 mm','Zohledni kabeláž a lokty.',['škola','počítač','šířka']],
    ['art-table','Hloubka výtvarného stolu','700–900 mm','cca 650 mm','Pro větší formáty a materiál.',['škola','výtvarná','stůl']],
    ['sink-height','Výška umyvadla ve třídě','700–850 mm','dle věku','U mateřské školy a mladších dětí nižší.',['škola','umyvadlo','výška']],
    ['display-height','Výška nástěnky pro dětské práce','střed cca 1000–1400 mm','dle věku','Děti mají na práce dobře vidět.',['škola','nástěnka','výška']]
  ]);

  add('obecne','DOPORUČENÍ',[
    ['passage-one','Komfortní průchod pro jednu osobu','900–1000 mm','cca 800 mm','U hlavních tras raději 1000 mm a více.',['průchod','šířka','interiér']],
    ['passage-two','Průchod pro míjení dvou osob','1200–1400 mm','cca 1100 mm','Pro frekventované trasy více.',['průchod','dvě osoby','šířka']],
    ['door-furniture','Odstup nábytku od dráhy dveří','min. 50–100 mm mimo obrys křídla','bez kolize','Ověř kliky, zárubeň a plné otevření.',['dveře','nábytek','kolize']],
    ['handle','Výška dveřní kliky','cca 900–1100 mm','dle dveří','U přístupných řešení ověř závazné požadavky.',['klika','dveře','výška']],
    ['switch','Výška vypínače','cca 900–1100 mm','dle konceptu','Důležitá je konzistence v celé stavbě.',['vypínač','výška','elektro']],
    ['socket-low','Běžná nízká zásuvka','cca 200–300 mm','dle projektu','Měřeno obvykle ke středu přístroje.',['zásuvka','výška','elektro']],
    ['socket-worktop','Zásuvka nad pracovní plochou','cca 1050–1200 mm','dle desky','Přizpůsob konkrétní výšce nábytku.',['zásuvka','pracovní plocha','výška']],
    ['thermostat','Výška termostatu','cca 1200–1500 mm','dle výrobce','Neumisťovat na přímé slunce nebo k tepelnému zdroji.',['termostat','výška','interiér']],
    ['art-center','Výška středu obrazu','cca 1450–1550 mm','dle prostoru','V obytném interiéru často funguje kolem úrovně očí.',['obraz','výška','stěna']],
    ['handrail','Ergonomická výška madla v interiéru','cca 900–1000 mm','ověřit předpisy','U schodiště a přístupnosti platí závazné požadavky.',['madlo','schodiště','výška']],
    ['curtain-track','Odstup kolejnice od stěny','80–150 mm','dle parapetu a závěsu','Musí obejít parapet, kliku a radiátor.',['závěs','kolejnice','odstup']],
    ['curtain-floor','Mezera závěsu nad podlahou','5–20 mm','dle stylu','Pro běžný provoz se vyhne špinění a drhnutí.',['závěs','podlaha','mezera']],
    ['radiator-furniture','Odstup nábytku od radiátoru','min. cca 100–200 mm','dle výrobce','Neblokovat proudění teplého vzduchu.',['radiátor','nábytek','odstup']],
    ['robot-vacuum','Světlá výška pod nábytkem pro robotický vysavač','cca 100–120 mm','dle modelu','Ověř konkrétní výšku robota.',['vysavač','nábytek','výška']],
    ['skirting','Běžná výška soklové lišty','60–120 mm','dle designu','Vyšší lišta lépe chrání stěnu.',['sokl','lišta','výška']],
    ['wall-protection','Výška omyvatelné ochrany stěny ve frekventovaném provozu','cca 900–1200 mm','dle provozu','Vhodné na chodbách, školách a gastro.',['stěna','ochrana','provoz']]
  ]);

  const existing=new Set(data.map(x=>x.id));
  rows.forEach(x=>{if(!existing.has(x.id)) data.push(x)});
  window.__TOOLBOX_INTERIOR_EXTRA_320=true;
})();