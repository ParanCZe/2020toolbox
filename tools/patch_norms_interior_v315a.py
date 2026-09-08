from pathlib import Path
import re

INDEX=Path('index.html')
DATA=Path('norms_data_v314y.js')
ENGINE=Path('norms_engine_v314y.js')

# ---------------- INDEX / VERSION / CHANGELOG ----------------
s=INDEX.read_text(encoding='utf-8-sig')
s=re.sub(r'(<div class="app-version" id="app-version">)V3\.14z(</div>)',r'\1V3.15a\2',s,count=1)
s=s.replace('; 20-20-TOOLBOX V3.14z\\n;','; 20-20-TOOLBOX V3.15a\\n;',1)
s=s.replace('norms_data_v314y.js?v=314z','norms_data_v314y.js?v=315a')
s=s.replace('norms_engine_v314y.js?v=314z','norms_engine_v314y.js?v=315a')
s=s.replace('<span class="whatsnew-ver">V3.14z</span>','<span class="whatsnew-ver">V3.15a</span>',1)
s=s.replace("const VERSION='V3.14z', KEY='20-20-toolbox-whatsnew-seen';","const VERSION='V3.15a', KEY='20-20-toolbox-whatsnew-seen';",1)
new_body='''<div class="whatsnew-body">
      <div class="whatsnew-item"><strong>Normy — přímé odkazy na konkrétní zdroj</strong><span>Karty a výsledky hledání jsou nyní klikatelné. U veřejných předpisů se otevře přímo příslušný paragraf; u ČSN se otevře detail normy v oficiálním katalogu, pokud je k dispozici.</span></div>
      <div class="whatsnew-item"><strong>Interiérové standardy — velké rozšíření</strong><span>Doplněny desítky praktických rozměrů pro kuchyně, koupelny, nábytek, ložnice, kanceláře, gastro, retail, hotely, školy, dětské prostory a další.</span></div>
      <div class="whatsnew-item"><strong>Interiérové standardy — chytré hledání</strong><span>Vyhledávací pole je nyní výrazně nahoře a hledá přes názvy, doporučené hodnoty, poznámky, kategorie a související výrazy.</span></div>
      <div class="whatsnew-item"><strong>Ovládání výsledků</strong><span>Výsledek normy už jen neposouvá pohled v Toolboxu — otevře rovnou zdroj. Vnitřní standardy se při hledání zvýrazní a zobrazí v přehledu.</span></div>
    </div>'''
s=re.sub(r'<div class="whatsnew-body">.*?</div>\s*<div class="whatsnew-actions">',new_body+'\n    <div class="whatsnew-actions">',s,count=1,flags=re.S)
INDEX.write_text(s,encoding='utf-8')

# ---------------- DATA: MANY MORE INTERIOR STANDARDS ----------------
d=DATA.read_text(encoding='utf-8-sig')
marker='window.TOOLBOX_INTERIOR_STANDARDS_V314Y = ['
if marker not in d:
    raise SystemExit('Interior standards array marker missing')

extra=r'''
  {id:'int-kitchen-base-depth',cat:'kuchyne',status:'BĚŽNÝ ROZMĚR',title:'Hloubka spodních kuchyňských skříněk',recommended:'cca 600 mm',minimum:'Běžný korpus 560–580 mm + čelo / přesah desky.',note:'Standardní modul pro většinu spotřebičů a pracovních desek.',keywords:['kuchyně','spodní skříňka','hloubka','linka']},
  {id:'int-kitchen-worktop-depth',cat:'kuchyne',status:'BĚŽNÝ ROZMĚR',title:'Hloubka pracovní desky',recommended:'600–650 mm',minimum:'U stěny obvykle alespoň 600 mm.',note:'Větší hloubka zvyšuje pracovní plochu, ale ověř dosah k zadní hraně.',keywords:['kuchyně','pracovní deska','hloubka']},
  {id:'int-kitchen-worktop-height',cat:'kuchyne',status:'DOPORUČENÍ',title:'Výška pracovní desky v kuchyni',recommended:'850–950 mm',minimum:'Přizpůsobit výšce hlavních uživatelů.',note:'Často se volí kolem 900 mm; přesná ergonomická výška závisí na postavě.',keywords:['kuchyně','pracovní deska','výška','ergonomie']},
  {id:'int-kitchen-upper-bottom',cat:'kuchyne',status:'DOPORUČENÍ',title:'Spodní hrana horních skříněk',recommended:'1350–1550 mm nad podlahou',minimum:'Mezera nad deskou často 500–650 mm.',note:'Výšku přizpůsob uživateli, digestoři a spotřebičům.',keywords:['horní skříňka','výška police','kuchyně','skříňky']},
  {id:'int-kitchen-upper-depth',cat:'kuchyne',status:'BĚŽNÝ ROZMĚR',title:'Hloubka horních kuchyňských skříněk',recommended:'300–380 mm',minimum:'Tak, aby nepřekážely při práci u desky.',note:'Větší hloubka zvyšuje kapacitu, ale může zhoršit ergonomii.',keywords:['horní skříňka','hloubka','kuchyně']},
  {id:'int-kitchen-aisle-one',cat:'kuchyne',status:'DOPORUČENÍ',title:'Průchod před kuchyňskou linkou',recommended:'1000–1200 mm',minimum:'cca 900 mm pro omezený provoz.',note:'Pro pohodlné otevírání zásuvek a průchod jedné osoby.',keywords:['kuchyně','průchod','mezera','linka']},
  {id:'int-kitchen-aisle-two',cat:'kuchyne',status:'DOPORUČENÍ',title:'Průchod mezi dvěma pracovními linkami',recommended:'1100–1300 mm',minimum:'cca 1000 mm podle provozu.',note:'Umožní současnou práci a otevírání protilehlých prvků.',keywords:['kuchyně','ostrůvek','průchod','dvě linky']},
  {id:'int-kitchen-island-depth',cat:'kuchyne',status:'BĚŽNÝ ROZMĚR',title:'Hloubka kuchyňského ostrůvku',recommended:'800–1200 mm',minimum:'cca 600 mm u jednoduchého pracovního bloku.',note:'Se sezením nebo skříňkami z obou stran bývá ostrůvek hlubší.',keywords:['ostrůvek','kuchyně','hloubka']},
  {id:'int-kitchen-bar-overhang',cat:'kuchyne',status:'DOPORUČENÍ',title:'Přesah desky pro barové sezení',recommended:'250–350 mm',minimum:'cca 200 mm pro krátkodobé sezení.',note:'Větší přesah zvyšuje prostor pro kolena.',keywords:['bar','ostrůvek','sezení','kolena','přesah']},
  {id:'int-kitchen-hood-hob',cat:'kuchyne',status:'DOPORUČENÍ',title:'Výška digestoře nad varnou deskou',recommended:'řídit se výrobcem; často cca 550–750 mm',minimum:'Nikdy ne pod minimem výrobce spotřebiče.',note:'Liší se podle typu varné desky a digestoře.',keywords:['digestoř','varná deska','kuchyně','výška']},

  {id:'int-bath-basin-height',cat:'koupelna',status:'DOPORUČENÍ',title:'Výška horní hrany umyvadla',recommended:'800–900 mm',minimum:'Přizpůsobit uživatelům a typu umyvadla.',note:'Běžná ergonomická montážní výška pro dospělé.',keywords:['umyvadlo','výška','koupelna']},
  {id:'int-bath-basin-side',cat:'koupelna',status:'DOPORUČENÍ',title:'Boční prostor u umyvadla',recommended:'min. cca 200 mm od osy hrany / komfortně více',minimum:'Ověřit konkrétní šířku umyvadla a baterie.',note:'Praktický odstup od boční stěny nebo vysoké skříně.',keywords:['umyvadlo','odstup','stěna','koupelna']},
  {id:'int-bath-basin-front',cat:'koupelna',status:'DOPORUČENÍ',title:'Volný prostor před umyvadlem',recommended:'700–900 mm',minimum:'cca 600 mm pro těsný provoz.',note:'Pro pohodlné stání, předklon a míjení.',keywords:['umyvadlo','prostor před','koupelna','odstup']},
  {id:'int-bath-wc-side',cat:'koupelna',status:'DOPORUČENÍ',title:'Boční odstup WC od překážky',recommended:'osa WC cca 400–450 mm od boční stěny',minimum:'Přesné minimum ověř podle požadavků projektu.',note:'Komfortní boční prostor výrazně zlepšuje používání.',keywords:['wc','toaleta','odstup','boční','koupelna']},
  {id:'int-bath-wc-front',cat:'koupelna',status:'DOPORUČENÍ',title:'Volný prostor před WC',recommended:'700–900 mm',minimum:'cca 600 mm v kompaktním řešení.',note:'U bezbariérového řešení platí jiné, větší požadavky.',keywords:['wc','toaleta','prostor před','odstup']},
  {id:'int-bath-shower-min',cat:'koupelna',status:'DOPORUČENÍ',title:'Rozměr sprchového koutu',recommended:'900 × 900 mm a více',minimum:'cca 800 × 800 mm pro kompaktní řešení.',note:'Walk-in sprcha bývá komfortnější od šířky přibližně 900–1000 mm.',keywords:['sprcha','sprchový kout','rozměr','koupelna']},
  {id:'int-bath-tub-space',cat:'koupelna',status:'DOPORUČENÍ',title:'Volný prostor před vanou',recommended:'700–900 mm',minimum:'cca 600 mm podle dispozice.',note:'Zohledni vstup do vany, ručníky a manipulaci.',keywords:['vana','odstup','koupelna','prostor před']},
  {id:'int-bath-mirror-height',cat:'koupelna',status:'DOPORUČENÍ',title:'Umístění zrcadla nad umyvadlem',recommended:'spodní hrana cca 1000–1200 mm',minimum:'Přizpůsobit výšce uživatelů a umyvadlu.',note:'Důležitější než pevná výška je rozsah odrazu pro očekávané uživatele.',keywords:['zrcadlo','umyvadlo','výška','koupelna']},
  {id:'int-bath-towel-hook',cat:'koupelna',status:'DOPORUČENÍ',title:'Výška háčku / držáku ručníku',recommended:'1100–1400 mm',minimum:'Dětem nebo bezbariérově níže.',note:'Vol podle typu ručníku a dosahu uživatelů.',keywords:['ručník','háček','držák','výška']},

  {id:'int-storage-wardrobe-depth',cat:'ulozne',status:'BĚŽNÝ ROZMĚR',title:'Hloubka šatní skříně pro ramínka',recommended:'600–650 mm',minimum:'cca 550 mm podle ramínek a dveří.',note:'Posuvné dveře obvykle vyžadují větší celkovou hloubku.',keywords:['šatní skříň','hloubka','ramínka','úložné']},
  {id:'int-storage-hanging-long',cat:'ulozne',status:'DOPORUČENÍ',title:'Světlá výška pro dlouhé oděvy',recommended:'1400–1700 mm',minimum:'Podle délky kabátů a šatů.',note:'Pro saka a košile stačí výrazně méně.',keywords:['šatna','tyč','kabát','šaty','výška']},
  {id:'int-storage-hanging-short',cat:'ulozne',status:'DOPORUČENÍ',title:'Světlá výška pro košile a saka',recommended:'900–1100 mm',minimum:'Přizpůsobit typu oděvů.',note:'Umožňuje dvě tyče nad sebou ve vysoké skříni.',keywords:['šatna','tyč','košile','sako','výška']},
  {id:'int-storage-shelf-spacing',cat:'ulozne',status:'DOPORUČENÍ',title:'Rozteč polic pro běžné oblečení',recommended:'250–350 mm',minimum:'Podle typu uložených věcí.',note:'Menší rozteč omezuje tvorbu vysokých nestabilních komínků.',keywords:['police','výška police','skříň','oblečení']},
  {id:'int-storage-books-depth',cat:'ulozne',status:'BĚŽNÝ ROZMĚR',title:'Hloubka knihovny',recommended:'250–320 mm',minimum:'cca 200 mm pro menší knihy.',note:'Velké obrazové knihy a šanony vyžadují více.',keywords:['knihovna','police','hloubka','knihy']},
  {id:'int-storage-shoe-depth',cat:'ulozne',status:'BĚŽNÝ ROZMĚR',title:'Hloubka botníku',recommended:'320–400 mm',minimum:'cca 250 mm u šikmých / výklopných systémů.',note:'Záleží na velikosti obuvi a konstrukci dvířek.',keywords:['botník','hloubka','boty','předsíň']},
  {id:'int-storage-coat-hook',cat:'predsin',status:'DOPORUČENÍ',title:'Výška věšáku na kabáty',recommended:'1500–1750 mm',minimum:'Dětské háčky zhruba 900–1200 mm.',note:'U sdílených prostor je praktické více výškových úrovní.',keywords:['věšák','kabát','háček','výška','předsíň']},
  {id:'int-storage-bench',cat:'predsin',status:'DOPORUČENÍ',title:'Výška lavice pro obouvání',recommended:'430–480 mm',minimum:'Podle cílových uživatelů.',note:'Hloubka sedací plochy bývá přibližně 350–450 mm.',keywords:['lavice','obouvání','předsíň','výška sedáku']},

  {id:'int-bedroom-bed-single',cat:'loznice',status:'BĚŽNÝ ROZMĚR',title:'Jednolůžko',recommended:'900 × 2000 mm',minimum:'Běžně 800 × 2000 mm u kompaktních řešení.',note:'Počítej navíc s rámem postele.',keywords:['postel','jednolůžko','ložnice','rozměr']},
  {id:'int-bedroom-bed-double',cat:'loznice',status:'BĚŽNÝ ROZMĚR',title:'Dvoulůžko',recommended:'1600–1800 × 2000 mm',minimum:'cca 1400 × 2000 mm pro kompaktní řešení.',note:'Konstrukce rámu může přidat desítky milimetrů na každé straně.',keywords:['postel','dvoulůžko','ložnice','rozměr']},
  {id:'int-bedroom-side-clearance',cat:'loznice',status:'DOPORUČENÍ',title:'Průchod vedle postele',recommended:'600–800 mm',minimum:'cca 500 mm u těsné dispozice.',note:'U skříně nebo zásuvek proti posteli je vhodné více.',keywords:['postel','průchod','ložnice','odstup']},
  {id:'int-bedroom-front-wardrobe',cat:'loznice',status:'DOPORUČENÍ',title:'Prostor před šatní skříní',recommended:'900–1100 mm',minimum:'cca 700 mm podle typu dveří.',note:'Křídlové dveře a současný průchod vyžadují větší odstup.',keywords:['skříň','průchod','ložnice','odstup']},
  {id:'int-bedroom-nightstand',cat:'loznice',status:'DOPORUČENÍ',title:'Výška nočního stolku',recommended:'přibližně v úrovni matrace ±100 mm',minimum:'Podle výšky postele.',note:'Praktické pro dosah vleže.',keywords:['noční stolek','postel','výška','ložnice']},

  {id:'int-living-sofa-depth',cat:'obyvak',status:'BĚŽNÝ ROZMĚR',title:'Celková hloubka sedačky',recommended:'850–1050 mm',minimum:'Kompaktní modely mohou být kolem 750–850 mm.',note:'Hlubší sedačka nemusí být pohodlná pro menší postavy bez polštářů.',keywords:['sedačka','pohovka','hloubka','obývák']},
  {id:'int-living-coffee-gap',cat:'obyvak',status:'DOPORUČENÍ',title:'Odstup konferenčního stolku od sedačky',recommended:'350–500 mm',minimum:'cca 300 mm.',note:'Musí umožnit průchod nohou a pohodlný dosah.',keywords:['konferenční stolek','sedačka','odstup','obývák']},
  {id:'int-living-tv-height',cat:'obyvak',status:'DOPORUČENÍ',title:'Výška středu TV',recommended:'přibližně ve výšce očí sedící osoby',minimum:'Obvykle cca 950–1200 mm podle sezení a velikosti TV.',note:'Vyhnout se dlouhodobému výraznému zaklánění hlavy.',keywords:['TV','televize','výška','obývák']},
  {id:'int-living-tv-distance',cat:'obyvak',status:'DOPORUČENÍ',title:'Pozorovací vzdálenost TV',recommended:'cca 1,2–2,0× úhlopříčka pro moderní 4K',minimum:'Záleží na rozlišení a preferencích.',note:'Vyšší rozlišení umožňuje kratší pozorovací vzdálenost.',keywords:['TV','televize','vzdálenost','obývák']},

  {id:'int-office-desk-height',cat:'pracovna',status:'DOPORUČENÍ',title:'Výška pracovního stolu',recommended:'720–760 mm',minimum:'Ideálně výškově nastavitelné podle uživatele.',note:'Lokty při práci by měly být přibližně v pravém úhlu bez zvedání ramen.',keywords:['pracovní stůl','výška','kancelář','ergonomie']},
  {id:'int-office-desk-depth',cat:'pracovna',status:'DOPORUČENÍ',title:'Hloubka pracovního stolu',recommended:'700–800 mm',minimum:'cca 600 mm pro notebook / kompaktní provoz.',note:'Velký monitor a dokumenty vyžadují hlubší desku.',keywords:['pracovní stůl','hloubka','kancelář','monitor']},
  {id:'int-office-chair-space',cat:'pracovna',status:'DOPORUČENÍ',title:'Prostor za pracovní židlí',recommended:'900–1200 mm',minimum:'cca 750 mm bez hlavního průchodu.',note:'Pokud za židlí vede komunikace, přidej další prostor.',keywords:['židle','pracovna','průchod','kancelář']},
  {id:'int-office-monitor',cat:'pracovna',status:'DOPORUČENÍ',title:'Vzdálenost očí od monitoru',recommended:'cca 500–800 mm',minimum:'Podle velikosti a rozlišení monitoru.',note:'Horní část obrazovky bývá přibližně v úrovni očí nebo lehce níže.',keywords:['monitor','vzdálenost','ergonomie','pracovna']},

  {id:'int-dining-table-height',cat:'jidlo',status:'BĚŽNÝ ROZMĚR',title:'Výška jídelního stolu',recommended:'740–760 mm',minimum:'Běžné židle se sedákem kolem 430–480 mm.',note:'Důležitý je rozdíl mezi sedákem a spodní hranou/deskou stolu.',keywords:['jídelní stůl','výška','jídelna']},
  {id:'int-dining-chair-space',cat:'jidlo',status:'DOPORUČENÍ',title:'Prostor na jednu osobu u stolu',recommended:'šířka 600–700 mm',minimum:'cca 550 mm pro těsnější sezení.',note:'U loketních opěrek je vhodné více.',keywords:['jídelní stůl','židle','místo na osobu','jídelna']},
  {id:'int-dining-behind-chair',cat:'jidlo',status:'DOPORUČENÍ',title:'Prostor za jídelní židlí',recommended:'900–1200 mm',minimum:'cca 750 mm bez průchodu.',note:'Pro průchod za sedící osobou je vhodné kolem 1100–1200 mm.',keywords:['jídelna','židle','průchod','odstup']},

  {id:'int-gastro-counter',cat:'gastro',status:'BĚŽNÝ ROZMĚR',title:'Výška barového pultu',recommended:'1050–1150 mm',minimum:'Podle typu barových židlí.',note:'Pro nižší pult a běžné židle se používají jiné výšky.',keywords:['bar','pult','gastro','výška']},
  {id:'int-gastro-bar-seat',cat:'gastro',status:'BĚŽNÝ ROZMĚR',title:'Výška sedáku barové židle',recommended:'750–800 mm pro pult 1050–1150 mm',minimum:'Zachovat pohodlný rozdíl mezi sedákem a pultem.',note:'Rozdíl bývá přibližně 250–320 mm.',keywords:['barová židle','pult','gastro','výška']},
  {id:'int-gastro-table-spacing',cat:'gastro',status:'DOPORUČENÍ',title:'Odstup mezi stoly v restauraci',recommended:'cca 900–1200 mm podle provozu',minimum:'Těsnější provoz lze řešit menším odstupem, ale s horším komfortem.',note:'Započítej vysunuté židle, obsluhu a případný hlavní průchod.',keywords:['restaurace','stoly','odstup','gastro']},
  {id:'int-gastro-service-aisle',cat:'gastro',status:'DOPORUČENÍ',title:'Hlavní obslužná ulička',recommended:'1200–1500 mm',minimum:'Podle typu provozu a přístupnosti.',note:'Vyšší intenzita obsluhy nebo obousměrný provoz vyžaduje více.',keywords:['restaurace','ulička','obsluha','gastro','průchod']},

  {id:'int-retail-aisle',cat:'retail',status:'DOPORUČENÍ',title:'Průchod mezi regály v retailu',recommended:'1200–1800 mm podle provozu',minimum:'Normové a přístupnostní požadavky ověř samostatně.',note:'Šířka závisí na intenzitě provozu, košících a charakteru prodejny.',keywords:['retail','obchod','regály','ulička','průchod']},
  {id:'int-retail-shelf-reach',cat:'retail',status:'DOPORUČENÍ',title:'Komfortní zóna polic v obchodě',recommended:'cca 700–1700 mm nad podlahou',minimum:'Nejčastěji používané zboží umisťuj do pohodlného dosahu.',note:'Přesný dosah se liší podle uživatelů a přístupnosti.',keywords:['retail','police','výška police','dosah']},
  {id:'int-retail-counter',cat:'retail',status:'DOPORUČENÍ',title:'Výška prodejního / recepčního pultu',recommended:'cca 900–1100 mm',minimum:'Pro přístupnou část pultu řešit samostatnou nižší úroveň.',note:'Rozlišuj práci ve stoje, v sedě a zákaznickou stranu.',keywords:['pult','retail','recepce','výška']},

  {id:'int-hotel-bed-side',cat:'hotel',status:'DOPORUČENÍ',title:'Průchod kolem hotelového lůžka',recommended:'700–900 mm',minimum:'Podle standardu pokoje a přístupnosti.',note:'U servisní strany postele je vhodné více místa.',keywords:['hotel','postel','průchod','pokoj']},
  {id:'int-hotel-luggage',cat:'hotel',status:'DOPORUČENÍ',title:'Výška police / lavice na zavazadlo',recommended:'450–650 mm',minimum:'Přizpůsobit typu zavazadel.',note:'Hloubka cca 450–600 mm bývá praktická pro kufr.',keywords:['hotel','kufr','zavazadlo','police','výška']},
  {id:'int-hotel-wardrobe',cat:'hotel',status:'BĚŽNÝ ROZMĚR',title:'Hloubka hotelové šatní skříně',recommended:'550–650 mm',minimum:'Podle způsobu věšení a dveří.',note:'Krátkodobé ubytování může mít menší úložný objem než byt.',keywords:['hotel','šatní skříň','hloubka']},

  {id:'int-kids-table',cat:'deti',status:'DOPORUČENÍ',title:'Výška dětského stolu',recommended:'cca 450–650 mm podle věku',minimum:'Vol podle výšky dítěte, ne jen věku.',note:'Sedák a stůl mají tvořit ergonomický pár.',keywords:['děti','dětský stůl','výška','škola']},
  {id:'int-kids-shelf',cat:'deti',status:'DOPORUČENÍ',title:'Výška dostupných dětských polic',recommended:'cca 300–1200 mm podle věku',minimum:'Nejčastější věci do bezpečného dosahu dítěte.',note:'Těžké předměty nízko a vysoký nábytek kotvit.',keywords:['děti','police','výška police','dosah']},
  {id:'int-kids-hook',cat:'deti',status:'DOPORUČENÍ',title:'Výška dětského věšáku',recommended:'cca 800–1200 mm',minimum:'Podle věku a výšky dítěte.',note:'Ve školkách je vhodné více úrovní podle věkových skupin.',keywords:['děti','věšák','háček','výška']},

  {id:'int-school-desk',cat:'skoly',status:'DOPORUČENÍ',title:'Školní pracovní plocha',recommended:'výšku volit podle antropometrie uživatelů',minimum:'Ideálně více velikostí nebo nastavitelné řešení.',note:'Pevnou univerzální výšku nelze vhodně použít pro všechny věkové skupiny.',keywords:['škola','lavice','stůl','výška','ergonomie']},
  {id:'int-school-aisle',cat:'skoly',status:'DOPORUČENÍ',title:'Průchody mezi nábytkem ve třídě',recommended:'navrhovat s rezervou pro pohyb a evakuaci',minimum:'Normové minimum ověř v příslušných předpisech.',note:'Rozměr závisí na uspořádání lavic, počtu žáků a únikových cestách.',keywords:['škola','třída','průchod','lavice']},

  {id:'int-general-seat-height',cat:'obecne',status:'DOPORUČENÍ',title:'Výška běžného sedáku',recommended:'430–480 mm',minimum:'Nízké lounge sezení může být cca 380–430 mm.',note:'Výška ovlivňuje pohodlí vstávání a vztah ke stolu.',keywords:['sedák','židle','výška','ergonomie']},
  {id:'int-general-seat-depth',cat:'obecne',status:'DOPORUČENÍ',title:'Hloubka sedáku židle',recommended:'400–450 mm',minimum:'Přizpůsobit cílové populaci.',note:'Příliš hluboký sedák tlačí do podkolenní jamky menších uživatelů.',keywords:['sedák','židle','hloubka','ergonomie']},
  {id:'int-general-standing-reach',cat:'obecne',status:'DOPORUČENÍ',title:'Komfortní svislý dosah dospělého ve stoje',recommended:'často cca 700–1800 mm',minimum:'Nejčastěji používané prvky umisťuj do střední části dosahu.',note:'Pro univerzální návrh je nutné počítat s rozdíly mezi uživateli.',keywords:['dosah','ergonomie','police','výška']},
  {id:'int-general-passage',cat:'obecne',status:'DOPORUČENÍ',title:'Komfortní průchod pro jednu osobu',recommended:'800–1000 mm',minimum:'Normové minimum závisí na konkrétním typu stavby.',note:'Pro míjení dvou osob a bezbariérový provoz je potřeba více.',keywords:['průchod','šířka','ergonomie','chodba']},
'''

if "id:'int-kitchen-base-depth'" not in d:
    d=d.replace(marker,marker+'\n'+extra,1)

# Direct paragraph anchors for public regulations where possible.
def anchor_line(line):
    if "source:'Vyhláška č. 146/2024 Sb.'" in line:
        m=re.search(r"section:'§\s*(\d+)",line)
        if m:
            line=re.sub(r"url:'https://www\.zakonyprolidi\.cz/cs/2024-146[^']*'",f"url:'https://www.zakonyprolidi.cz/cs/2024-146#p{m.group(1)}'",line)
    if "source:'Vyhláška č. 131/2024 Sb.'" in line:
        m=re.search(r"section:'§\s*(\d+)",line)
        if m:
            line=re.sub(r"url:'https://www\.zakonyprolidi\.cz/cs/2024-131[^']*'",f"url:'https://www.zakonyprolidi.cz/cs/2024-131#p{m.group(1)}'",line)
    return line

d='\n'.join(anchor_line(line) for line in d.split('\n'))
DATA.write_text(d,encoding='utf-8')

# ---------------- ENGINE: CLICK THROUGH + BETTER INTERIOR SEARCH ----------------
e=ENGINE.read_text(encoding='utf-8-sig')

# More synonyms for natural queries.
e=e.replace("dokumentace:['dokumentace','DPS','povolení','pasport']", "dokumentace:['dokumentace','DPS','povolení','pasport'], kuchyne:['kuchyně','linka','ostrůvek','pracovní deska'], koupelna:['koupelna','umyvadlo','wc','sprcha','vana'], nabytek:['nábytek','skříň','police','stůl','židle','postel'], odstup:['odstup','mezera','vzdálenost','prostor'], hloubka:['hloubka','hluboký','hluboká'], hotel:['hotel','ubytování','pokoj'], obchod:['retail','obchod','prodejna','regál'], skola:['škola','třída','lavice','děti']")

# Extend interior categories.
e=re.sub(r"const ICATS=\{.*?\};let icat=''", "const ICATS={kuchyne:'Kuchyně',koupelna:'Koupelna',ulozne:'Úložné prostory',predsin:'Předsíň',loznice:'Ložnice',obyvak:'Obývák',pracovna:'Pracovna',jidlo:'Jídelna',gastro:'Gastro',retail:'Retail / obchody',hotel:'Hotely',deti:'Dětské prostory',skoly:'Školy',obecne:'Obecné'};let icat=''", e, count=1)

# Add source URL helper and make norm cards open source directly.
helper=r'''
function normSourceUrl(x){
  let u=String(x.url||'');
  const sec=String(x.section||'');
  let m=sec.match(/§\s*(\d+)/);
  if(String(x.source||'').includes('146/2024')&&m)return 'https://www.zakonyprolidi.cz/cs/2024-146#p'+m[1];
  if(String(x.source||'').includes('131/2024')&&m)return 'https://www.zakonyprolidi.cz/cs/2024-131#p'+m[1];
  if(u)return u;
  return 'https://csnonline.agentura-cas.cz/';
}
function openNormSource(id){const x=(window.TOOLBOX_NORMS_V314Y||[]).find(n=>n.id===id);if(!x)return;window.open(normSourceUrl(x),'_blank','noopener');}
'''
if 'function normSourceUrl(x)' not in e:
    e=e.replace("function badgeType(x){return String(x.type||'').includes('ČSN')?'csn':'law'}", "function badgeType(x){return String(x.type||'').includes('ČSN')?'csn':'law'}\n"+helper,1)

new_norm_card=r'''function normCard(x,full=false){const u=normSourceUrl(x);return `<div class="${full?'ny-entry':'ny-result'}" id="ny-${esc(x.id)}" role="link" tabindex="0" onclick="if(!event.target.closest('a'))openNormSource('${esc(x.id)}')" onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();openNormSource('${esc(x.id)}')}" title="Otevřít zdroj"><div class="ny-entry-top"><div><h3>${esc(x.title)}</h3><div class="ny-meta">${esc(x.source)} · ${esc(x.section||'')}</div>${x.value?`<div class="ny-value">${esc(x.value)}</div>`:''}</div><a class="ny-link" target="_blank" rel="noopener" href="${esc(u)}">Otevřít zdroj ↗</a></div><div class="ny-badges"><span class="ny-badge ${badgeType(x)}">${esc(x.type)}</span><span class="ny-badge">${esc(NCATS[x.cat]?.[0]||x.cat)}</span></div><p class="ny-note">${esc(x.summary)}</p></div>`}'''
e=re.sub(r"function normCard\(x,full=false\)\{.*?\}(?=\nfunction renderNormBrowser)",new_norm_card,e,count=1,flags=re.S)

# Interior result clicks jump to full card; whole search is prominent and live-searches.
new_int_html=r'''function interiorHtml(){return `<button class="back-btn" onclick="closeTool()">← Zpět do menu</button><h1>Interiérové standardy <small class="menu-status">BETA</small></h1><div class="muted">Ergonomie, praktické rozměry, nábytek, sanita, odstupy a návrhové hodnoty. Doporučení nejsou automaticky normovým minimem.</div><div class="ny-hero"><div class="ny-search"><input id="iy-search" type="search" placeholder="Co hledáš? např. výška police, odstup umyvadla, hloubka skříně, prostor kolem stolu…" oninput="interiorYSearch()" onkeydown="if(event.key==='Enter')interiorYSearch()"><button class="action" onclick="interiorYSearch()">Hledat ve všem</button></div><div class="ny-hint">Hledání prochází všechny interiérové standardy, doporučené rozměry, poznámky a související výrazy. Můžeš napsat i běžnou frázi jako „kolik místa před WC“ nebo „výška horní skříňky“.</div></div><div class="iy-legend"><div><b>DOPORUČENÍ</b><br>ergonomická / praktická návrhová hodnota</div><div><b>BĚŽNÝ ROZMĚR</b><br>obvyklý rozměr výrobku nebo nábytku</div><div><b>POZOR</b><br>pokud je hodnota normová, ověř ji v aplikaci Normy</div></div><div class="iy-cats">${Object.entries(ICATS).map(([k,v])=>`<button class="iy-chip" data-cat="${k}" onclick="interiorYCat('${k}')">${esc(v)}</button>`).join('')}<button class="iy-chip" onclick="interiorYInit()">Vše</button></div><div class="ny-head"><b>VÝSLEDKY HLEDÁNÍ</b><span id="iy-search-count"></span></div><div id="iy-results" class="iy-results"></div><div class="ny-head"><b>PŘEHLED STANDARDŮ</b><span id="iy-count"></span></div><div id="iy-grid" class="iy-grid"></div><div class="ny-warning"><b>Projektantská pomůcka:</b> hodnoty označené DOPORUČENÍ nebo BĚŽNÝ ROZMĚR nejsou samy o sobě právním předpisem. U přístupnosti, požární bezpečnosti, únikových cest a dalších regulovaných oblastí vždy ověř požadavky v aplikaci Normy a v aktuálním zdroji.</div>`}'''
e=re.sub(r"function interiorHtml\(\)\{return `.*?`\}",new_int_html,e,count=1,flags=re.S)

# Search count and show only matching full cards after search for immediate usefulness.
e=e.replace("function renderInteriorSearch(list,q){const host=document.getElementById('iy-results');if(!host)return;host.innerHTML=q?(list.length?list.slice(0,30).map(x=>intCard(x,false)).join(''):'<div class=\"ny-empty\">Nic jsem nenašel. Zkus jiné slovo.</div>'):''}", "function renderInteriorSearch(list,q){const host=document.getElementById('iy-results'),cnt=document.getElementById('iy-search-count');if(!host)return;if(cnt)cnt.textContent=q?`${list.length} výsledků`:'';host.innerHTML=q?(list.length?list.slice(0,40).map(x=>intCard(x,false)).join(''):'<div class=\"ny-empty\">Nic jsem nenašel. Zkus jiné slovo.</div>'):''}")
e=e.replace("window.interiorYSearch=()=>{const q=document.getElementById('iy-search')?.value?.trim()||'',db=window.TOOLBOX_INTERIOR_STANDARDS_V314Y||[];if(!q){renderInteriorSearch([],'');renderInterior(icat?db.filter(x=>x.cat===icat):db);return}const ranked=db.map(x=>[score(x,q),x]).filter(a=>a[0]>0).sort((a,b)=>b[0]-a[0]).map(a=>a[1]);renderInteriorSearch(ranked,q)};", "window.interiorYSearch=()=>{const q=document.getElementById('iy-search')?.value?.trim()||'',db=window.TOOLBOX_INTERIOR_STANDARDS_V314Y||[];if(!q){renderInteriorSearch([],'');renderInterior(icat?db.filter(x=>x.cat===icat):db);return}const ranked=db.map(x=>[score(x,q),x]).filter(a=>a[0]>0).sort((a,b)=>b[0]-a[0]).map(a=>a[1]);renderInteriorSearch(ranked,q);renderInterior(ranked)};")

ENGINE.write_text(e,encoding='utf-8')

# ---------------- SAFETY ----------------
idx=INDEX.read_text(encoding='utf-8')
dat=DATA.read_text(encoding='utf-8')
eng=ENGINE.read_text(encoding='utf-8')
assert 'V3.15a' in idx
assert 'norms_data_v314y.js?v=315a' in idx and 'norms_engine_v314y.js?v=315a' in idx
assert "const VERSION='V3.15a'" in idx
assert "id:'int-kitchen-base-depth'" in dat
assert "id:'int-general-passage'" in dat
assert 'function normSourceUrl(x)' in eng
assert 'openNormSource' in eng
assert 'oninput="interiorYSearch()"' in eng
assert "retail:'Retail / obchody'" in eng
print('V3.15a norms links + expanded interior standards applied')
