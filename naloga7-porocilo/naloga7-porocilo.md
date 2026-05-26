# Poročilo izsledkov KPI analize

**Avtor:** Vladimir Sabo

## Kratek opis domene

BI rešitev obravnava prometne nesreče v ZDA skupaj z vremenskimi pogoji in kakovostjo zraka. Izhodišče iz predloga BI rešitve je bilo ugotoviti, kdaj in kje se nesreče pojavljajo, kako dolgo traja njihova obravnava ter ali se pri tem kaže povezava z okoljskimi podatki, predvsem z AQI. Nadzorne plošče so zato pripravljene kot interaktivna analiza, kjer se vrednosti KPI-jev preračunajo glede na izbrane filtre.

## Uporabljene meritve in dimenzije

**Meritve:**

- število nesreč;
- trajanje nesreče v minutah;
- mediana in p90 trajanja nesreč;
- delež AQI opazovanj s slabim zrakom (`AQI > 100`);
- povprečni AQI;
- korelacije med merami nesreč in deležem slabega zraka.

**Dimenzije:**

- čas oziroma časovno obdobje;
- zvezna država in okraj;
- resnost nesreče;
- vremenski pogoj;
- primarni cestni signal oziroma cestni kontekst;
- AQI opredeljujoči parameter.

## KPI 1: Število nesreč na časovno enoto

**Opis in izračun:** KPI šteje prometne nesreče v izbrani časovni enoti. Osnovni izračun je `COUNT(*)`, pri čemer se rezultat lahko razčleni po času, lokaciji in resnosti.

![KPI 1 - pogostost nesreč](../naloga6/screenshots/db-kpi1-accident-frequency-filtered.png)

**Interpretacija:** KPI 1 potrjuje cilj iz naloge 1: pridobiti osnovno sliko pogostosti nesreč po času in lokaciji. Nefiltriran pogled kaže izrazito rast števila evidentiranih nesreč od leta 2016 naprej, z opaznimi mesečnimi nihanji. Filtriran primer pokaže, da se analiza lahko zoži na konkretne države, okraje in stopnje resnosti. V izbranem primeru je zadnji mesečni prikaz 927 nesreč, trend pa omogoča primerjavo z neposredno prejšnjim mesecem.

Dodatne vizualizacije odgovarjajo na PA1 in PA2 iz predloga BI. Grafikon po dnevu v tednu in uri pokaže, da se vzorci nesreč razlikujejo po času dneva, kar podpira iskanje najbolj obremenjenih časovnih intervalov. Grafikon resnosti skozi čas pokaže, katere stopnje resnosti prevladujejo v izbranem obdobju. Razvrstitev okrajev pokaže geografsko koncentracijo nesreč; v filtriranem primeru izstopajo izbrani okraji v New Yorku in Massachusettsu.

## KPI 2: Trajanje obravnave nesreč

**Opis in izračun:** V predlogu BI je bil KPI 2 definiran kot povprečno trajanje `AVG(endtime - starttime)`. Pri izdelavi nadzorne plošče se je pokazalo, da povprečje preveč popačijo zelo dolgi dogodki, zato sta za vizualno interpretacijo uporabljeni mediana in p90 trajanja. Osamelci niso odstranjeni; samo prikaz je prilagojen tako, da ostane berljiv.

![KPI 2 - trajanje nesreč](../naloga6/screenshots/db-kpi2-accident-duration-filtered-ca.png)

**Interpretacija:** KPI 2 odgovarja na vprašanje, kje in pod katerimi pogoji so nesreče operativno zahtevnejše. V kalifornijskem filtriranem primeru je mediana trajanja 132,10 minute. Trend mediane in p90 kaže, da tipično trajanje ostaja bistveno bolj stabilno kot povprečje, medtem ko p90 še vedno opozori na daljše primere.

Dodatne vizualizacije pokrivajo PA3 in PA4 iz predloga BI. Trajanje po vremenskih pogojih pokaže, da se tipično trajanje spreminja glede na vreme; pri snegu, toči in podobnih pogojih so vrednosti lahko opazno višje. Grafikon po resnosti in cestnem signalu kaže, da cestni kontekst in resnost skupaj vplivata na trajanje dogodka. Razvrstitev okrajev po številu nesreč doda pomemben kontekst: lokacija z daljšim trajanjem ni nujno tudi lokacija z največjim številom dogodkov.

Pri KPI 2 je posebej pomembno, da nadzorna plošča ni samo statično poročilo. Z uporabo filtrov je bilo mogoče izločiti zelo specifičen primer vremenskega pogoja `Tornado`, kjer se pokaže izrazit osamelec pri trajanju obravnave nesreče. Tak primer potrjuje, da uporabnik od BI orodja ne dobi samo končnega odgovora, ampak raziskovalno okolje, kjer lahko z nekaj preizkušanja najde nenavadne vzorce in jih nato interpretira previdno.

![KPI 2 - izločen primer vremenskega osamelca](../naloga6/screenshots/db-kpi2-accident-duration-filtered-tornado.png)

## KPI 3: Delež slabega zraka po AQI

**Opis in izračun:** KPI 3 meri delež AQI opazovanj, kjer je `AQI > 100`. Izračun je `COUNT(opazovanj z AQI > 100) / COUNT(vseh AQI opazovanj)`. Pri prikazu se delež izračuna uteženo iz števila opazovanj, ne kot preprosto povprečje že agregiranih odstotkov.

![KPI 3 - kakovost zraka](../naloga6/screenshots/db-kpi3-air-quality-filtered.png)

**Interpretacija:** KPI 3 izpolni cilj iz predloga BI, kjer je bilo predvideno ugotavljanje deleža kakovosti zraka prek meje dobrega/slabega zraka. V filtriranem primeru za izbrane okraje v New Yorku je zadnji prikaz deleža slabega zraka 0,00, trend pa pokaže, da se slabi dnevi pojavljajo občasno in niso enakomerno razporejeni.

Dodatne vizualizacije podpirajo PA5 in PA6. Trend primerja povprečni AQI in delež slabega zraka ter pokaže gibanje skozi čas. Razvrstitev okrajev razkrije, kateri izbrani okraji imajo višji delež slabega zraka. Kolobarni grafikon po opredeljujočem parametru pokaže, da v izbranem primeru večino slabih opazovanj pojasnjuje ozon, del pa PM2.5. To je pomembno, ker KPI ne pove samo, da je zrak slab, ampak tudi kateri parameter je k temu največ prispeval.

## Dodatna analiza: povezava nesreč in kakovosti zraka

Predlog BI je kot širši cilj navedel iskanje povezav med nesrečami, vremenom in kakovostjo zraka. Zato je pripravljena še skupna nadzorna plošča, ki primerja mere nesreč z deležem slabega zraka na zrnu zvezna država/mesec.

![Povezava nesreč in kakovosti zraka](../naloga6/screenshots/db-combo-accidents-air-quality-filtered.png)

V filtriranem primeru so korelacije negativne in šibke: število nesreč proti deležu slabega zraka je `-0,1293`, trajanje proti deležu slabega zraka `-0,0877`, resnost proti deležu slabega zraka pa `-0,1041`. To pomeni, da v izbranem kontekstu ni močne linearne povezave med slabim zrakom in obravnavanimi merami nesreč. Rezultat je pomemben, ker ne potrjuje preproste domneve, da slabši zrak neposredno sovpada z več nesrečami ali daljšo obravnavo. Vizualizacije je treba brati kot analizo povezanosti, ne kot dokaz vzročnosti.

## Kritično branje podatkov

Pri nefiltriranem KPI 1 trendu je v začetku leta 2020 opazen izrazit padec števila nesreč. Iz samih podatkov ne moremo dokazati vzroka, vendar širši družbeni kontekst jasno opozarja na obdobje COVID-19, zaprtja javnega življenja in močan upad prometa. To je dober primer, zakaj BI rezultatov ne smemo brati izolirano: podatki pokažejo vzorec, razlaga pa mora upoštevati tudi dogajanje zunaj same podatkovne zbirke.

Celoten nabor podatkov se je izkazal kot zelo bogat za nadaljnje podatkovno rudarjenje. Štiri pripravljene nadzorne plošče niso zgornja meja take rešitve, ampak dokaz koncepta. Z več časa bi bilo smiselno pripraviti še bolj specializirane nadzorne plošče za posamezne vremenske pojave, skupine lokacij, nenavadno dolge obravnave nesreč, sezonske vzorce ali specifične kombinacije nesreč in AQI parametrov. Superset je za tak pristop primeren, ker omogoča hitro spreminjanje perspektive z nekaj filtri in grafičnimi prerezi.

## Executive summary

BI rešitev je uspešno naslovila cilje iz naloge 1. KPI 1 pokaže časovne in geografske koncentracije nesreč ter omogoča razlago pogostosti po resnosti. KPI 2 pokaže, da je za trajanje nesreč primernejša robustna interpretacija z mediano in p90, saj povprečje preveč obvladujejo osamelci. KPI 3 pokaže delež slabega zraka in omogoča razlago po okrajih ter opredeljujočih parametrih AQI.

Skupna analiza nesreč in kakovosti zraka ne pokaže močne linearne povezave med deležem slabega zraka in številom, trajanjem ali resnostjo nesreč. Glavna vrednost BI rešitve je zato v interaktivnem pregledu vzorcev po času, prostoru in dimenzijah ter v tem, da omogoča preverjanje domnev na izbranem kontekstu namesto sklepanja iz ene statične številke. Posebej pomembno je, da rešitev omogoča odkrivanje osamelcev in širših vzorcev, ki jih vnaprej pripravljen statični izpis pogosto ne bi razkril.
