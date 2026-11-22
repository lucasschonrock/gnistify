# Gnistify

En WoW-addon til guilden **Gnisterne** på WoW Forever. Længe leve gnisten!

## Hvad kan den?

- **Ding:** når nogen i guilden stiger i level, lyder ding-lyden, og der står
  fx *"DING! Navn er dinget level X! Længe leve gnisten!"* i chatten og stort på
  skærmen. Teksten skifter, så det ikke bliver kedeligt. Den, der dinger, skriver det
  også i guild chat.
- **PvP-drab:** når en fra guilden får killing blow på en fjende, ser alle med addonen
  fx *"Navn (med Anna og Bo) gnistede Offer (lvl 34 Mage) til døde i Zone! (dagens drab
  nr. 3)"* i chatten, og der spilles en lyd. Teksten skifter fra gang til gang. "Med"
  er gruppemedlemmer tæt på, og tallet er, hvor mange drab personen har fået i dag.
  Selvom I er flere i gruppen, kommer beskeden kun én gang.
- **PvP-tavle:** `/gnist top` viser, hvem i guilden der har flest drab i world PvP i dag,
  denne uge, denne måned og nogensinde (BG og arena tæller ikke). Nr. 1 får en
  ærestitel: **Dagens Gnistsprutter**, **Ugens Brandfakkel**, **Månedens Bålkonge** og
  **Gnistkejseren** (nr. 2 og 3 nogensinde er **Gnistprinsen** og **Gnistridderen**).
  Titlen står ved navnet, når du dræber nogen, og alle får besked i chatten og en lyd,
  når en titel skifter hænder (lyden kan slås fra i `/gnist`). Lederne får den gamle
  elite-drage om deres portræt: guld til Gnistkejseren, sølv med vinger til månedens
  nr. 1 og sølv til dagens og ugens nr. 1. Den ses på dit eget portræt, i gruppen og når du har dem i target. Tavlen deles mellem alle med addonen, også med dem der var offline. Du kan
  også klikke på gnisten ved minimappet (højreklik åbner indstillingerne), og holder du
  musen over den, kan du se, hvem der har titlerne lige nu.
- **Dueller:** når to fra guilden duellerer mod hinanden, står resultatet i chatten med
  en fræk kommentar, fx *"Navn smadrede Navn i en duel!"*. Stikker en af, får han en
  ekstra hård kommentar. Antal vundne dueller står i en ekstra kolonne, **Dueller**, i
  PvP-tavlen (`/gnist top`). Kun dueller mellem to fra guilden tæller, og hver duel tælles
  kun én gang. Beskeden kan slås fra i `/gnist`. Dueller nulstilles sammen med PvP-tavlen.
- **Leder i BG:** vælg én i gruppen som leder (shot caller), og tryk én tast for at
  tage lederens mål. Vælg lederen i det lille **Leder**-vindue (knappen *Vælg*). Vinduet
  dukker selv op i BG og dungeons, og ellers åbner du det fra `/gnist` (*Åbn
  leder-vindue*). Du kan også bruge `/gnist leder`, mens du har personen i target. Valget deles automatisk med alle
  i gruppen, der har addonen. Sæt tasten under *Indstillinger → Keybindings →
  Gnistify → "Mål lederens mål"*, eller tryk *Lav makro* i `/gnist` og træk makroen op på en
  action bar. Du kan også bare klikke på Leder-vinduet. Flyt vinduet ved at
  højreklikke og trække. Vinduet viser lederens mål og siger til, hvis du ikke har det samme, og
  der kan lyde et lille ping, når lederen skifter til en ny fjende (slås til i `/gnist`). Lederen kan kun
  skiftes uden for kamp (et valg i kamp virker, så snart kampen er slut).
- **Fiskeri:** når en fra guilden fanger noget særligt (grønt eller bedre, sjældne fisk
  som Old Ironjaw, eller en kiste), ser alle med addonen fx *"Bo halede [Old Ironjaw]
  op af vandet i Ironforge! (dagens fisk nr. 47)"*. Fiskeri-skill fejres for hver 25
  point, og 75/150/225/300 fejres som et ding. 25, 50, 100 ... fisk på en dag bliver
  også meldt ud, og `/gnist fisk` viser dagens bedste fiskere. Mens du fisker, skrues
  der op for lydeffekter og ned for musik, så du nemt hører plasket.
- **Streaks:** addonen tæller, hvor mange dage i træk hver af dine karakterer logger ind.
  Ved 3, 7, 14, 30, 50, 100, 150, 200 og 365 dage (og derefter hver 100.) fejrer den det
  med en besked i chatten, stort på skærmen og en lyd hos alle med addonen, og du skriver
  det også i guild chat. Det sker højst én gang om dagen. Slås til og fra i `/gnist`, og
  `/gnist streak` viser din streak og din rekord.
- **Professioner:** addonen deler dine professioner og skill med guilden, så alle kan slå
  op, hvem der kan hvad. `/gnist prof alchemy` viser fx *"Alchemy: Navn 225/300, Bo 150/150
  (3 dage gammel)"*, bedste skill først. Navnene er de engelske (Alchemy, Blacksmithing,
  Enchanting, Engineering, Herbalism, Leatherworking, Mining, Skinning, Tailoring, Cooking,
  First Aid, Fishing), og du kan forkorte dem (`alch`, `bs`, `ench`, `eng`, `herb`, `lw`,
  `skin`, `tailor`, `cook`, `fa`, `fish`). Også dem, der er offline, kan ses, med seneste
  kendte skill. `/gnist prof` alene viser, hvor mange der har hver profession. Du kan slå
  deling fra i `/gnist`.
- **Gnister i zonen:** når du kommer ind i en ny zone, skriver Gnistify én linje i chatten
  med de guildmedlemmer, der er online i samme zone, fx *"3 gnister i Stranglethorn Vale:
  Bo Hansen (34), Tim (31), Mink Jageren (36)"*. Virker for alle i guilden, også dem uden
  addonen. Ingen besked i dungeons og battlegrounds, eller hvis du lige har været i zonen.
  Kan slås fra i `/gnist`.
- **Episk loot:** når en fra guilden looter noget episk (lilla) eller legendarisk
  (orange), ser alle med addonen fx *"Gnisten lyser lilla! Navn har fået fingrene i
  [Item]!"* i chatten, og der spilles en lyd. Teksten skifter fra gang til gang, og
  legendariske ting får ekstra meget begejstring. Håndlavede ting og ting købt hos
  en vendor tæller ikke. Alt kan slås til og fra i `/gnist`.
- **:gnist:** skriv `:gnist:` i chatten for at vise en lille gnist. Kun dem med addonen
  ser billedet.

## Installation

1. Hent den nyeste zip fra **Releases** eller CurseForge.
2. Pak den ud i `World of Warcraft/_forever_/Interface/AddOns/`, så mappen hedder
   `Gnistify`.
3. Genstart WoW.

## Kommandoer

| Kommando | Hvad den gør |
|---|---|
| `/gnist` | Åbner indstillingerne (Indstillinger → AddOns → Gnistify), hvor du kan slå hver funktion til og fra |
| `/gnist top` | Viser guildens PvP-tavle |
| `/gnist` | Åbner indstillinger, hvor du kan slå hver funktion til og fra |
| `/gnist top` | Viser guildens PvP-tavle (også med vundne dueller) |
| `/gnist reset` | Foreslår at nulstille PvP-tavlen. Alle med Gnistify bliver spurgt, og ved 4 ja starter alle drab forfra |
| `/gnist fisk` | Viser dagens fangst i guilden |
| `/gnist streak` | Viser, hvor mange dage i træk du har logget ind, og din rekord |
| `/gnist prof Alchemy` | Viser, hvem i guilden der har professionen, og deres skill (`/gnist prof` alene viser antal pr. profession) |
| `/gnist her` | Viser guildens gnister i din zone |
| `/gnist her Zone` | Viser guildens gnister i en zone, der starter med det du skriver (fx `/gnist her stran`) |
| `/gnist zoner` | Viser hvor mange gnister der er online i hver zone |
| `/gnist hjælp` | Viser alle kommandoer |
| `/gnist leder` | Gør dit target til leder, eller åbner leder-vinduet |
| `/gnist leder Navn` / `mig` / `ingen` | Vælger en leder ved navn, dig selv, eller ingen |
| `/gnist makro` | Laver makroen "GnistMål", som tager lederens mål |

## Ny version (for udviklere)

Hver gang du pusher til `main`, laver GitHub automatisk en ny version (fx `v1.0.1`),
bygger zip-filen og lægger den op på GitHub Releases og CurseForge.

- Hvis du vil hoppe til et større versionsnummer, så lav selv et tag, fx `v1.1.0`, og
  push det.
- Ændringer, der kun rører README, CLAUDE.md, `art/` eller `.github/`, giver ikke en ny
  version.
- Skriv `[skip ci]` i commit-beskeden, hvis en push ikke skal blive til en version.
