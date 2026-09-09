(()=>{
  const data=window.TOOLBOX_INTERIOR_STANDARDS_V314Y;
  if(!Array.isArray(data)) return;
  const packs={
    kuchyne:[
      ['Šířka vysoké potravinové skříně','450–600 mm','U úzkých modulů lze 300–400 mm.'],
      ['Výška soklu kuchyňské linky','80–150 mm','Podle systému skříněk a ergonomie.'],
      ['Přesah pracovní desky přes čela','20–40 mm','Alespoň tak, aby chránil čela před kapající vodou.'],
      ['Volný prostor nad varnou deskou','650–750 mm','Řídit se především výrobcem spotřebiče.'],
      ['Vzdálenost dřezu od rohu','min. 300 mm','Lépe 450 mm a více.'],
      ['Pracovní plocha mezi dřezem a varnou deskou','600–1200 mm','Alespoň cca 400 mm v malé kuchyni.'],
      ['Odkládací plocha u lednice','min. 300 mm','Ideálně 400–600 mm.'],
      ['Odkládací plocha u trouby','min. 300 mm','Ideálně 400–600 mm.'],
      ['Výška vestavné trouby','střed cca 900–1200 mm','Dvířka by neměla být příliš vysoko.'],
      ['Výška mikrovlnné trouby','spodní hrana cca 900–1200 mm','Vyhnout se umístění vysoko nad úrovní očí.'],
      ['Průchod za barovou židlí','900–1100 mm','Min. cca 800 mm bez frekventovaného průchodu.'],
      ['Šířka místa u baru na osobu','550–650 mm','Min. cca 500 mm.']
    ],
    koupelna:[
      ['Šířka umyvadla pro jednu osobu','500–700 mm','Kompaktní umyvadla mohou mít 400–450 mm.'],
      ['Hloubka umyvadlové desky','450–550 mm','Kompaktně cca 400 mm.'],
      ['Rozteč dvou umyvadel','min. 800–900 mm osově','Komfortně 1000 mm a více.'],
      ['Šířka walk-in vstupu','700–900 mm','Min. cca 600 mm podle dispozice.'],
      ['Hloubka walk-in sprchy','1000–1400 mm','Kompaktně cca 900 mm.'],
      ['Výška sprchové baterie','1000–1200 mm','Přizpůsobit typu baterie a uživatelům.'],
      ['Výška hlavové sprchy','2000–2200 mm','Min. podle výšky nejvyššího uživatele.'],
      ['Výška ruční sprchy v držáku','1100–1400 mm','Podle typu sprchy.'],
      ['Výška držáku toaletního papíru','600–750 mm','Umístit v dosahu z WC.'],
      ['Boční dosah držáku papíru od WC','200–300 mm před osou sedu','Podle dispozice.'],
      ['Výška ovládacího tlačítka WC','900–1100 mm','Podle systému a uživatelů.'],
      ['Prostor před pračkou','800–1000 mm','Min. cca 700 mm.']
    ],
    ulozne:[
      ['Hloubka skříně na složené oblečení','400–500 mm','Min. cca 350 mm.'],
      ['Hloubka polic ve spíži','300–450 mm','Menší hloubka zlepšuje přehled.'],
      ['Šířka průchodu v šatně','900–1100 mm','Min. cca 800 mm.'],
      ['Průchod mezi skříněmi proti sobě','1100–1400 mm','Min. cca 1000 mm.'],
      ['Výška šatní tyče pro dospělé','1600–1750 mm','Nižší pro menší uživatele.'],
      ['Výška spodní šatní tyče ve dvojitém věšení','900–1050 mm','Podle délky oděvů.'],
      ['Výška horní police ve skříni','1900–2100 mm','Vyšší již spíše pro sezónní věci.'],
      ['Výška zásuvky na spodní prádlo','700–1100 mm','Podle sestavy skříně.'],
      ['Výška lavice v šatně','430–480 mm','Podobně jako běžná sedací výška.'],
      ['Hloubka lavice v šatně','350–450 mm','Min. cca 320 mm.'],
      ['Police na boty – vertikální rozteč','180–250 mm','Vyšší pro kotníkové boty.'],
      ['Prostor pro vysavač / mop','šířka cca 300–450 mm','Výška dle typu zařízení.']
    ],
    predsin:[
      ['Volný prostor za vstupními dveřmi','min. 900 × 900 mm','Více při častém provozu.'],
      ['Šířka předsíňové lavice','600–1000 mm','Min. cca 500 mm.'],
      ['Výška věšáků pro dospělé','1600–1750 mm','Nižší háčky pro děti.'],
      ['Výška věšáků pro děti','900–1200 mm','Podle věku.'],
      ['Hloubka otevřené niky na kabáty','550–650 mm','Min. cca 500 mm.'],
      ['Šířka botníkové lavice na osobu','500–600 mm','Min. cca 450 mm.'],
      ['Hloubka konzolového stolku v předsíni','250–350 mm','Kompaktně cca 200 mm.'],
      ['Průchod vedle otevřeného botníku','min. 900 mm','Komfortně 1000–1100 mm.'],
      ['Výška zrcadla v předsíni','horní hrana cca 1900–2100 mm','Spodní hrana podle požadovaného záběru.'],
      ['Šířka celopostavového zrcadla','400–600 mm','Min. cca 350 mm.'],
      ['Místo pro kočárek v předsíni','cca 700 × 1200 mm','Podle konkrétního modelu.'],
      ['Místo pro mokrou obuv','hloubka cca 350–450 mm','S omyvatelným povrchem.']
    ],
    loznice:[
      ['Průchod po straně dvojlůžka','600–800 mm','Min. cca 500 mm.'],
      ['Průchod u nohou postele','700–900 mm','Min. cca 600 mm.'],
      ['Šířka nočního stolku','400–600 mm','Min. cca 300 mm.'],
      ['Výška nočního stolku','v úrovni matrace ±100 mm','Podle výšky lůžka.'],
      ['Výška matrace nad podlahou','450–600 mm','Nižší postele jsou designové, ale hůře se vstává.'],
      ['Šířka jednolůžka','900–1000 mm','Kompaktně 800 mm.'],
      ['Šířka dvojlůžka','1600–1800 mm','Kompaktně 1400 mm.'],
      ['Délka lůžka','2000–2100 mm','Pro vysoké osoby 2100–2200 mm.'],
      ['Průchod mezi postelí a skříní','900–1100 mm','Min. cca 800 mm.'],
      ['Prostor před zásuvkovou komodou','800–1000 mm','Min. cca 700 mm.'],
      ['Výška nástěnného světla u postele','1000–1300 mm','Podle výšky lůžka a typu svítidla.'],
      ['Výška čtecího světla nad matrací','600–900 mm','Podle směrování svítidla.']
    ],
    obyvak:[
      ['Vzdálenost sedačky od konferenčního stolku','350–500 mm','Min. cca 300 mm.'],
      ['Průchod za sedačkou','800–1000 mm','Min. cca 700 mm.'],
      ['Průchod mezi dvěma sedačkami','800–1000 mm','Min. cca 700 mm.'],
      ['Výška konferenčního stolku','350–450 mm','Obvykle podobná nebo mírně nižší než sedák.'],
      ['Hloubka konferenčního stolku','500–800 mm','Podle velikosti sezení.'],
      ['Šířka místa na sedačce na osobu','550–650 mm','Min. cca 500 mm.'],
      ['Výška sedáku sedačky','400–460 mm','Nízké lounge typy mohou mít méně.'],
      ['Hloubka sedáku sedačky','500–600 mm','Lounge typy mohou být hlubší.'],
      ['TV – výška středu obrazovky','cca 1000–1200 mm','Podle výšky očí vsedě a vzdálenosti.'],
      ['TV – vzdálenost sledování','cca 1,5–2,5× úhlopříčka','Závisí na rozlišení a preferencích.'],
      ['Prostor pro otevření relaxačního křesla','800–1200 mm před křeslem','Podle mechanismu.'],
      ['Průchod kolem krbových kamen','dispozičně cca 800 mm a více','Bezpečné odstupy vždy podle výrobce.']
    ],
    pracovna:[
      ['Výška pracovního stolu','720–760 mm','Nastavitelný stůl je vhodnější.'],
      ['Hloubka pracovního stolu','700–800 mm','Min. cca 600 mm pro notebook.'],
      ['Šířka pracovního místa','1200–1600 mm','Min. cca 1000 mm.'],
      ['Volný prostor pro nohy pod stolem','šířka min. 600 mm','Výška cca 650 mm a více.'],
      ['Vzdálenost monitoru od očí','500–800 mm','Podle velikosti monitoru.'],
      ['Výška horní hrany monitoru','v úrovni očí nebo mírně níž','U velkých monitorů může být střed níže.'],
      ['Průchod za pracovní židlí','900–1200 mm','Min. cca 800 mm.'],
      ['Prostor pro odsunutí židle','800–1000 mm','Min. cca 700 mm.'],
      ['Výška police nad pracovním stolem','spodní hrana 1200–1500 mm','Podle dosahu a monitoru.'],
      ['Výška zásuvek nad stolem','900–1200 mm','Podle způsobu použití.'],
      ['Akustický odstup dvou pracovních míst','1200–1600 mm osově','Více v otevřeném prostoru.'],
      ['Šířka stolové desky pro dvě osoby vedle sebe','2400–3200 mm','Min. cca 2200 mm.']
    ],
    jidlo:[
      ['Šířka místa u jídelního stolu na osobu','550–650 mm','Min. cca 500 mm.'],
      ['Hloubka jídelního místa na osobu','350–450 mm','Min. cca 300 mm.'],
      ['Šířka stolu pro dvě osoby proti sobě','800–1000 mm','Min. cca 750 mm.'],
      ['Výška jídelního stolu','740–760 mm','Běžně cca 750 mm.'],
      ['Výška sedáku jídelní židle','430–470 mm','Běžně cca 450 mm.'],
      ['Průchod za židlí bez další komunikace','750–900 mm','Min. cca 700 mm.'],
      ['Průchod za obsazenou židlí','1000–1200 mm','Min. cca 900 mm.'],
      ['Průchod mezi dvěma řadami židlí','1200–1500 mm','Min. cca 1100 mm.'],
      ['Průměr kulatého stolu pro 4 osoby','1000–1200 mm','Kompaktně cca 900 mm.'],
      ['Průměr kulatého stolu pro 6 osob','1300–1500 mm','Min. cca 1200 mm.'],
      ['Délka obdélníkového stolu pro 6 osob','1600–2000 mm','Min. cca 1500 mm.'],
      ['Výška závěsného svítidla nad stolem','600–800 mm nad deskou','Podle velikosti svítidla a oslnění.']
    ],
    gastro:[
      ['Šířka pracovního modulu v gastro kuchyni','600–900 mm','Podle zařízení.'],
      ['Průchod mezi gastro linkami','1200–1500 mm','Min. cca 1000 mm při malém provozu.'],
      ['Průchod za obsluhou u výdeje','1000–1200 mm','Min. cca 900 mm.'],
      ['Výška pracovní plochy v gastro','850–950 mm','Podle činnosti a výšky pracovníků.'],
      ['Hloubka pracovní plochy v gastro','600–800 mm','Min. cca 600 mm.'],
      ['Výška barového pultu pro hosty','1050–1150 mm','Běžně cca 1100 mm.'],
      ['Výška barové pracovní plochy obsluhy','850–950 mm','Podle technologie.'],
      ['Šířka barového místa na hosta','550–650 mm','Min. cca 500 mm.'],
      ['Průchod mezi stoly v restauraci','900–1200 mm','Min. cca 800 mm bez obslužné trasy.'],
      ['Vzdálenost hran stolů proti sobě','1400–1800 mm','Min. cca 1200 mm.'],
      ['Servisní ulička za lavicí','800–1000 mm','Min. cca 700 mm.'],
      ['Výška spodní hrany police nad gastro deskou','1400–1600 mm','Podle dosahu a zařízení.']
    ],
    retail:[
      ['Hlavní průchod v menší prodejně','1200–1500 mm','Min. podle typu provozu a předpisů.'],
      ['Vedlejší průchod mezi regály','900–1200 mm','Min. cca 800 mm v malém provozu.'],
      ['Průchod pro dva nákupní vozíky','1800–2200 mm','Min. cca 1600 mm.'],
      ['Hloubka nástěnného regálu','300–600 mm','Podle sortimentu.'],
      ['Hloubka oboustranného regálu','700–1200 mm','Podle sortimentu.'],
      ['Výška nejvyšší běžně dosažitelné police','1600–1800 mm','Vyšší police spíše pro zásobu.'],
      ['Výška pokladního pultu','850–1100 mm','Podle typu obsluhy.'],
      ['Hloubka pokladního pultu','600–800 mm','Podle technologie.'],
      ['Prostor za pokladnou','900–1200 mm','Min. cca 800 mm.'],
      ['Šířka zkušební kabiny','1000–1200 mm','Kompaktně cca 900 mm.'],
      ['Hloubka zkušební kabiny','1200–1500 mm','Kompaktně cca 1000 mm.'],
      ['Výška věšáku ve zkušební kabině','1500–1700 mm','Nižší doplňkový háček cca 1000–1200 mm.']
    ],
    hotel:[
      ['Šířka průchodu po straně hotelového lůžka','600–800 mm','Min. cca 500 mm.'],
      ['Průchod u nohou hotelového lůžka','800–1000 mm','Min. cca 700 mm.'],
      ['Šířka zavazadlové lavice','700–1000 mm','Min. cca 600 mm.'],
      ['Hloubka zavazadlové lavice','450–550 mm','Min. cca 400 mm.'],
      ['Výška zavazadlové lavice','450–600 mm','Podle designu pokoje.'],
      ['Šířka hotelového pracovního stolu','900–1200 mm','Min. cca 800 mm.'],
      ['Hloubka hotelového pracovního stolu','500–650 mm','Min. cca 450 mm.'],
      ['Prostor před minibarem','700–900 mm','Min. cca 600 mm.'],
      ['Výška ovládání světel u postele','600–900 mm nad podlahou','Podle výšky lůžka.'],
      ['Výška zásuvky u nočního stolku','600–900 mm','Podle konstrukce čela.'],
      ['Hloubka hotelové šatní skříně','550–650 mm','Min. cca 500 mm.'],
      ['Volný prostor před hotelovou skříní','900–1100 mm','Min. cca 800 mm.']
    ],
    deti:[
      ['Výška dětského pracovního stolu 3–6 let','460–550 mm','Podle výšky dítěte.'],
      ['Výška dětské židle 3–6 let','260–320 mm','Podle výšky dítěte.'],
      ['Výška pracovního stolu 6–10 let','550–650 mm','Podle výšky dítěte.'],
      ['Výška židle 6–10 let','320–380 mm','Podle výšky dítěte.'],
      ['Výška pracovního stolu 10–14 let','650–720 mm','Podle výšky dítěte.'],
      ['Výška věšáků v dětském pokoji','900–1300 mm','Podle věku.'],
      ['Výška horní dostupné police pro malé děti','1000–1200 mm','Bezpečně níže podle věku.'],
      ['Hloubka dětské šatní skříně','500–600 mm','Kompaktně cca 450 mm.'],
      ['Volný herní prostor v pokoji','min. cca 1500 × 1500 mm','Podle věku a aktivit.'],
      ['Výška spodní hrany otevřené police nad postelí','min. cca 900 mm nad matrací','Lépe bez tvrdých polic přímo nad hlavou.'],
      ['Průchod kolem dětské postele','600–800 mm','Min. cca 500 mm.'],
      ['Výška nočního světla pro dítě','500–800 mm','Podle lůžka.']
    ],
    skoly:[
      ['Šířka pracovního místa žáka','600–700 mm','Min. podle typu lavice.'],
      ['Hloubka školní lavice','500–700 mm','Podle věku a vybavení.'],
      ['Průchod mezi řadami lavic','800–1000 mm','Min. cca 700 mm.'],
      ['Průchod podél stěny ve třídě','900–1200 mm','Min. cca 800 mm.'],
      ['Odstup první řady od tabule','2000–3000 mm','Podle velikosti tabule a výšky očí.'],
      ['Výška spodní hrany tabule','800–1000 mm','Nižší pro mladší děti.'],
      ['Výška horní hrany tabule','1800–2200 mm','Podle věku a místnosti.'],
      ['Šířka učitelského stolu','1200–1600 mm','Min. cca 1000 mm.'],
      ['Volný prostor před tabulí','1200–1800 mm','Min. cca 1000 mm.'],
      ['Šířka skříňky v šatně na žáka','250–350 mm','Podle typu ukládání.'],
      ['Hloubka školní šatní skříňky','450–550 mm','Min. cca 400 mm.'],
      ['Výška háčku v MŠ','900–1200 mm','Podle věku dětí.']
    ],
    obecne:[
      ['Běžný hlavní průchod v interiéru','900–1200 mm','Min. podle funkce a předpisů.'],
      ['Vedlejší průchod mezi nábytkem','700–900 mm','Kompaktně cca 600 mm.'],
      ['Prostor před otevíravými dveřmi skříně','800–1000 mm','Min. cca 700 mm.'],
      ['Prostor před zásuvkami','800–1000 mm','Min. cca 700 mm.'],
      ['Výška kliky dveří','900–1100 mm','Běžně cca 1000–1050 mm.'],
      ['Výška vypínačů','900–1100 mm','Podle koncepce projektu.'],
      ['Výška běžných zásuvek','250–350 mm','Podle soklu, nábytku a použití.'],
      ['Výška termostatu','1400–1600 mm','Mimo přímé slunce a zdroje tepla.'],
      ['Výška domovního telefonu / ovládacího panelu','1400–1600 mm','Dle přístupnosti může být níže.'],
      ['Výška středu obrazu na stěně','cca 1450–1550 mm','Podle výšky očí a nábytku.'],
      ['Odstup nábytku od radiátoru','100–300 mm','Řídit se typem topidla a výrobcem.'],
      ['Průchod mezi stolem a stěnou','900–1200 mm','Min. cca 800 mm.']
    ]
  };
  const existing=new Set(data.map(x=>x.id));
  let n=0;
  for(const [cat,rows] of Object.entries(packs)){
    rows.forEach((r,i)=>{
      const id=`int319-${cat}-${String(i+1).padStart(2,'0')}`;
      if(existing.has(id)) return;
      const title=r[0], recommended=r[1], minimum=r[2]||'';
      const status=/^(Šířka|Hloubka|Výška|Délka|Průměr)/.test(title)?'BĚŽNÝ ROZMĚR':'DOPORUČENÍ';
      data.push({id,cat,status,title,recommended,minimum,note:'Praktické ergonomické doporučení; vždy ověř konkrétní provoz, výrobek a případné závazné požadavky projektu.',keywords:[cat,title.toLowerCase(),'ergonomie','interiér','rozměry']});
      existing.add(id); n++;
    });
  }
  window.__TOOLBOX_INTERIOR_EXTRA_319_COUNT=n;
})();