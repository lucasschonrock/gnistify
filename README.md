# Gnistify

En WoW-addon til guilden **Gnisterne** på WoW Forever. Længe leve gnisten!

## Hvad kan den?

- **Ding:** når nogen i guilden stiger i level, lyder ding-lyden, og der står
  *"DING! Navn er dinget level X! Længe leve gnisten!"* i chatten og stort på skærmen.
  Den, der dinger, skriver det også i guild chat.
- **PvP-drab:** når en fra guilden får killing blow på en fjende, ser alle med addonen
  *"Navn gnistede Offer (lvl 34 Mage) til døde i Zone!"* i chatten, og der spilles en lyd.
  Selvom I er flere i gruppen, kommer beskeden kun én gang.
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
| `/gnist` | Åbner indstillinger, hvor du kan slå hver funktion til og fra |
| `/gnist hjælp` | Viser alle kommandoer |

## Ny version (for udviklere)

Lav et git-tag, fx `v1.1.0`, og push det. Så bygger GitHub automatisk zip-filen og
lægger den op på GitHub Releases og CurseForge.
